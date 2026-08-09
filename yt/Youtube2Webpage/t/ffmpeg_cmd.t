use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

require "$RealBin/../yt-to-webpage.pl";

my @cmd = build_ffmpeg_cmd(125, "video.webm", "images/00-02-05.jpg");
is_deeply(\@cmd, [
    'ffmpeg', '-ss', 125, '-nostdin', '-i', 'video.webm',
    '-frames:v', '1', '-q:v', '2', '-vf', 'scale=1024:-1',
    'images/00-02-05.jpg',
], "builds the correct single-frame capture command");

done_testing();
