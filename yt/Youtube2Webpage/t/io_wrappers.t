use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);

require "$RealBin/../yt-to-webpage.pl";

sub write_fake_executable {
    my ($dir, $name, $script_body) = @_;
    my $path = "$dir/$name";
    open(my $fh, ">", $path) or die $!;
    print $fh "#!/bin/sh\n$script_body\n";
    close $fh;
    chmod 0755, $path;
    return $path;
}

my $fakebin = tempdir(CLEANUP => 1);
local $ENV{PATH} = "$fakebin:$ENV{PATH}";

# --- run_ytdlp ---
write_fake_executable($fakebin, "yt-dlp", "echo 'boom' >&2; exit 1");
eval { run_ytdlp('yt-dlp', '--fake-arg') };
like($@, qr/yt-dlp exited with status 1/, "run_ytdlp dies with exit status on failure");

write_fake_executable($fakebin, "yt-dlp", "echo 'video.webm'");
is(run_ytdlp('yt-dlp', '--fake-arg'), "video.webm\n", "run_ytdlp returns captured stdout on success");

# --- run_whisper ---
write_fake_executable($fakebin, "whisper", "exit 1");
eval { run_whisper('whisper', '--fake-arg') };
like($@, qr/whisper exited with status 1/, "run_whisper dies on failure");

write_fake_executable($fakebin, "whisper", "exit 0");
ok(run_whisper('whisper', '--fake-arg'), "run_whisper returns true on success");

# --- invoke_claude_cli ---
write_fake_executable($fakebin, "claude", "cat >/dev/null; echo 'error output' >&2; exit 1");
eval { invoke_claude_cli("some prompt") };
like($@, qr/claude CLI exited with status 1/, "invoke_claude_cli dies on failure");

write_fake_executable($fakebin, "claude", q{cat >/dev/null; echo '{"result":"[1,2]"}'});
like(invoke_claude_cli("some prompt"), qr/\[1,2\]/, "invoke_claude_cli returns captured stdout on success");

# --- run_ffmpeg_capture (never dies, even on failure) ---
write_fake_executable($fakebin, "ffmpeg", "exit 1");
my $ok = eval { run_ffmpeg_capture('ffmpeg', '-fake') };
ok(!$@, "run_ffmpeg_capture does not die on failure");
ok(!$ok, "run_ffmpeg_capture returns false on failure");

write_fake_executable($fakebin, "ffmpeg", "exit 0");
ok(run_ffmpeg_capture('ffmpeg', '-fake'), "run_ffmpeg_capture returns true on success");

done_testing();
