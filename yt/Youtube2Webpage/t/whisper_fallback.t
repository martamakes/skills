use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);

require "$RealBin/../yt-to-webpage.pl";

my $empty_dir = tempdir(CLEANUP => 1);
ok(!has_vtt_files($empty_dir), "false when directory has no .vtt files");

my $dir_with_vtt = tempdir(CLEANUP => 1);
open(my $fh, ">", "$dir_with_vtt/captions.vtt") or die $!;
print $fh "WEBVTT\n";
close $fh;
ok(has_vtt_files($dir_with_vtt), "true when directory has a .vtt file");

my @cmd = build_whisper_cmd("My Video.webm");
is_deeply(\@cmd, ['whisper', 'My Video.webm', '--model', 'turbo', '--output_format', 'vtt'],
    "whisper command uses turbo model, vtt output, no forced language");

done_testing();
