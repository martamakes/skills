#!/usr/bin/perl

use warnings;
use strict;
use autodie;
use JSON::PP qw(decode_json);
use IPC::Open2;

sub timestamp_to_seconds {
    my ($ts) = @_;
    if ($ts =~ /^(\d+):(\d+):(\d+)(?:\.\d+)?$/) {
        return $1 * 3600 + $2 * 60 + $3;
    }
    die "Invalid timestamp format: $ts";
}

sub parse_vtt {
    my ($vtt_path) = @_;
    open(my $fh, "<", $vtt_path);
    my $timestamp_seen = 0;
    my $this_start = 0;
    my $last_text_line = '';
    my @moments;
    while (my $line = <$fh>) {
        chomp $line;
        if (!$timestamp_seen) {
            if ($line =~ /^\d\d:\d\d/) {
                $timestamp_seen = 1;
            } else {
                next;
            }
        }
        next if $line =~ /^\s*$/;
        next if $line =~ /<\/c>$/;
        if ($line =~ /(\d\d:\d\d:\d\d\.\d\d\d) --> (\d\d:\d\d:\d\d\.\d\d\d)/) {
            $this_start = $1;
            next;
        }
        next if $line eq $last_text_line;
        push @moments, { timestamp => $this_start, text => $line };
        $last_text_line = $line;
    }
    close $fh;
    return @moments;
}

sub build_transcript_text {
    my ($moments) = @_;
    my $text = '';
    foreach my $m (@$moments) {
        my $seconds = timestamp_to_seconds($m->{timestamp});
        $text .= "[$seconds] $m->{text}\n";
    }
    return $text;
}

sub check_transcript_size {
    my ($text) = @_;
    my $len = length($text);
    if ($len > 500_000) {
        die "Transcript too large to analyze in a single call ($len characters, limit 500000). Chunking is not implemented yet.\n";
    }
    return 1;
}

sub build_claude_prompt {
    my ($transcript_text) = @_;
    return <<"PROMPT";
You are analyzing a video transcript. Each line is formatted as "[seconds] text",
where "seconds" is the timestamp in the video where that line starts.

Identify the KEY MOMENTS in this transcript: points where the speaker moves to a
new sub-topic or starts a new piece of content (a new concept, a new demo, a new
example). Do NOT select standalone quotes or remarks within the same topic block.

Respond with ONLY a JSON array of integers - the "seconds" value of each key
moment, in ascending order. No explanation, no markdown, no extra text.

Example response: [125, 340, 812, 1290]

Transcript:
$transcript_text
PROMPT
}

sub parse_claude_response {
    my ($raw_output) = @_;
    my $outer;
    eval { $outer = decode_json($raw_output); };
    die "Claude CLI did not return valid JSON wrapper: $@\nRaw output:\n$raw_output\n" if $@;

    my $result_text = $outer->{result};
    die "Claude CLI response has no 'result' field.\nRaw output:\n$raw_output\n"
        unless defined $result_text;

    unless ($result_text =~ /(\[.*\])/s) {
        die "Could not find a JSON array in Claude's response.\nResponse text:\n$result_text\n";
    }
    my $array_text = $1;

    my $timestamps;
    eval { $timestamps = decode_json($array_text); };
    die "Claude's JSON array did not parse: $@\nArray text:\n$array_text\n" if $@;

    die "Claude returned zero key moments.\n" unless @$timestamps;

    for my $t (@$timestamps) {
        die "Claude returned a non-numeric timestamp: '$t'\n" unless $t =~ /^\d+(?:\.\d+)?$/;
    }

    return @$timestamps;
}

sub select_moment_texts {
    my ($all_moments, $selected_timestamps) = @_;
    my @selected;
    foreach my $target (@$selected_timestamps) {
        my $best;
        my $best_diff;
        foreach my $m (@$all_moments) {
            my $seconds = timestamp_to_seconds($m->{timestamp});
            my $diff = abs($seconds - $target);
            if (!defined $best_diff || $diff < $best_diff) {
                $best_diff = $diff;
                $best = { timestamp_seconds => $seconds, text => $m->{text} };
            }
        }
        push @selected, $best if $best;
    }
    @selected = sort { $a->{timestamp_seconds} <=> $b->{timestamp_seconds} } @selected;
    return @selected;
}

sub seconds_to_filename {
    my ($seconds) = @_;
    my $h = int($seconds / 3600);
    my $m = int(($seconds % 3600) / 60);
    my $s = $seconds % 60;
    return sprintf("%02d-%02d-%02d", $h, $m, $s);
}

sub escape_html {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

sub generate_html {
    my ($selected, $url) = @_;
    my $html = <<"HEADER";
<html>
<head>
 <link rel="stylesheet" type="text/css" href="styles.css" />
</head>
<body>

<h1>Youtube transcript</h1>
Source: <a href="$url" target="_blank">$url</a>

<ul>
HEADER
    foreach my $m (@$selected) {
        my $seconds = $m->{timestamp_seconds};
        my $ts_filename = seconds_to_filename($seconds);
        my $escaped_text = escape_html($m->{text});
        $html .= qq{<li>
	<div class="grab"><img src="images/$ts_filename.jpg" /></div><div class="subtitle"><span id="$seconds">$escaped_text</span>
<a href="${url}&t=${seconds}" target="blank" class="videolink">#</a>
	</div></li>\n};
    }
    $html .= "\n</ul>\n</body>\n</html>";
    return $html;
}

sub prompt_subtitle_language {
    my ($in_fh) = @_;
    $in_fh //= \*STDIN;
    print STDERR "Preferred subtitle language (e.g. en, es) [en]: ";
    my $answer = <$in_fh>;
    chomp $answer if defined $answer;
    $answer = 'en' unless defined $answer && length $answer;
    return $answer;
}

sub build_ytdlp_cmd {
    my ($url, $lang) = @_;
    return (
        'yt-dlp',
        '--cookies-from-browser', 'chrome',
        '--sleep-requests', '1',
        '-f', 'bv*[height<=720]+ba/b[height<=720]',
        '--write-auto-subs', '--write-subs',
        '--sub-lang', $lang,
        '--print', 'filename',
        '--no-simulate',
        $url,
    );
}

sub has_vtt_files {
    my ($dir) = @_;
    opendir(my $dh, $dir);
    my @vtts = grep { /\.vtt$/ } readdir($dh);
    closedir $dh;
    return scalar(@vtts) > 0;
}

sub build_whisper_cmd {
    my ($video_file) = @_;
    return ('whisper', $video_file, '--model', 'turbo', '--output_format', 'vtt');
}

sub build_ffmpeg_cmd {
    my ($seconds, $video_file, $output_path) = @_;
    return (
        'ffmpeg', '-ss', $seconds, '-nostdin', '-i', $video_file,
        '-frames:v', '1', '-q:v', '2', '-vf', 'scale=1024:-1',
        $output_path,
    );
}

sub run_ytdlp {
    no autodie qw(close);
    my (@cmd) = @_;
    open(my $ph, "-|", @cmd) or die "Failed to run yt-dlp: $!\n";
    my $output = do { local $/; <$ph> };
    close $ph;
    my $exit = $? >> 8;
    if ($exit != 0) {
        die "yt-dlp exited with status $exit.\nOutput:\n$output\n";
    }
    return $output;
}

sub run_whisper {
    my (@cmd) = @_;
    system(@cmd);
    my $exit = $? >> 8;
    if ($exit != 0) {
        die "whisper exited with status $exit while transcribing audio.\n";
    }
    return 1;
}

sub run_ffmpeg_capture {
    my (@cmd) = @_;
    system(@cmd);
    my $exit = $? >> 8;
    return $exit == 0;
}

sub invoke_claude_cli {
    my ($prompt) = @_;
    my ($reader, $writer);
    my $pid = open2($reader, $writer, 'claude', '-p', '--output-format', 'json');
    print $writer $prompt;
    close $writer;
    my $output = do { local $/; <$reader> };
    close $reader;
    waitpid($pid, 0);
    my $exit = $? >> 8;
    if ($exit != 0) {
        die "claude CLI exited with status $exit.\nOutput:\n$output\n";
    }
    return $output;
}

sub run {
    my $slug = shift @ARGV;
    my $url = shift @ARGV;

    if (!$url || $url !~ m|^https://www\.youtube\.com|) {
        print STDERR "Usage:\n";
        print STDERR "$0 project-name \"https://www.youtube.com/watch?v=jNQXAC9IVRw\"\n";
        exit 1;
    }

    mkdir($slug) unless -d $slug;
    chdir($slug);

    my $lang = prompt_subtitle_language();

    my @ytdlp_cmd = build_ytdlp_cmd($url, $lang);
    my $ytdlp_output = run_ytdlp(@ytdlp_cmd);
    (my $video_file = $ytdlp_output) =~ s/\s+\z//;

    unless (has_vtt_files('.')) {
        print STDERR "No subtitles found for this video. Falling back to local Whisper transcription...\n";
        my @whisper_cmd = build_whisper_cmd($video_file);
        run_whisper(@whisper_cmd);
        unless (has_vtt_files('.')) {
            die "Whisper did not produce a .vtt file. Aborting.\n";
        }
    }

    my ($vtt_path) = glob('*.vtt');
    die "No .vtt file available after download/transcription.\n" unless $vtt_path;

    my @moments = parse_vtt($vtt_path);
    die "Transcript is empty after parsing $vtt_path.\n" unless @moments;

    my $transcript_text = build_transcript_text(\@moments);
    check_transcript_size($transcript_text);

    my $prompt = build_claude_prompt($transcript_text);
    my $claude_output = invoke_claude_cli($prompt);
    my @selected_timestamps = parse_claude_response($claude_output);

    my @selected_moments = select_moment_texts(\@moments, \@selected_timestamps);

    mkdir('images') unless -d 'images';
    foreach my $m (@selected_moments) {
        my $ts_filename = seconds_to_filename($m->{timestamp_seconds});
        my $image_path = "images/$ts_filename.jpg";
        my @ffmpeg_cmd = build_ffmpeg_cmd($m->{timestamp_seconds}, $video_file, $image_path);
        my $ok = run_ffmpeg_capture(@ffmpeg_cmd);
        unless ($ok) {
            print STDERR "Warning: failed to capture screenshot at $m->{timestamp_seconds}s, skipping.\n";
        }
    }

    system('cp', '../styles.css', '.') if -f '../styles.css';

    my $html = generate_html(\@selected_moments, $url);
    open(my $out, '>', 'index.html');
    print $out $html;
    close $out;

    print "Done. Open index.html in $slug/ to view the result.\n";
}

run() unless caller();
1;
