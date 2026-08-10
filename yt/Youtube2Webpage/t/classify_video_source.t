use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use Cwd qw(abs_path getcwd);

require "$RealBin/../yt-to-webpage.pl";

# --- undef / empty arg ---
is(classify_video_source(undef), undef, "undef arg returns undef");
is(classify_video_source(""), undef, "empty string arg returns undef");

# --- YouTube URL forms ---
for my $url (
    "https://www.youtube.com/watch?v=abc123",
    "https://youtube.com/watch?v=abc123",
    "https://m.youtube.com/watch?v=abc123",
    "https://youtu.be/abc123",
) {
    is_deeply(classify_video_source($url), { type => 'youtube', url => $url },
        "recognizes $url as a youtube source");
}

# http (non-TLS) is intentionally NOT recognized
is(classify_video_source("http://www.youtube.com/watch?v=abc123"), undef,
    "http (non-TLS) youtube link is not recognized");

# --- non-existent path ---
is(classify_video_source("/no/such/file-hopefully-1234.mp4"), undef,
    "non-existent local path returns undef");

# --- existing file, unrecognized extension ---
my $dir = tempdir(CLEANUP => 1);
open(my $txt_fh, ">", "$dir/notes.txt") or die $!;
print $txt_fh "hello";
close $txt_fh;
is_deeply(classify_video_source("$dir/notes.txt"),
    { type => 'invalid_extension', path => "$dir/notes.txt" },
    "existing file with unrecognized extension");

# --- existing file, recognized extension (absolute path given) ---
open(my $mov_fh, ">", "$dir/clip.mov") or die $!;
print $mov_fh "fake video bytes";
close $mov_fh;
is_deeply(classify_video_source("$dir/clip.mov"),
    { type => 'local', path => abs_path("$dir/clip.mov") },
    "existing .mov file with absolute path given");

# --- existing file, recognized extension, uppercase extension ---
open(my $mp4_fh, ">", "$dir/CLIP.MP4") or die $!;
close $mp4_fh;
is_deeply(classify_video_source("$dir/CLIP.MP4"),
    { type => 'local', path => abs_path("$dir/CLIP.MP4") },
    "extension match is case-insensitive");

# --- existing file, relative path given: must resolve to absolute ---
my $orig_cwd = getcwd();
chdir($dir) or die $!;
my $result = classify_video_source("clip.mov");
chdir($orig_cwd) or die $!;
is_deeply($result, { type => 'local', path => abs_path("$dir/clip.mov") },
    "relative path is resolved to absolute before chdir happens elsewhere");

done_testing();
