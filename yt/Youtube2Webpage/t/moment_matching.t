use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

require "$RealBin/../yt-to-webpage.pl";

my @moments = (
    { timestamp => "00:00:00.000", text => "Intro" },
    { timestamp => "00:02:05.000", text => "Topic A" },
    { timestamp => "00:05:40.000", text => "Topic B" },
    { timestamp => "00:10:00.000", text => "Closing" },
);

# Claude returns timestamps that don't exactly match any moment's own
# timestamp: 2s is close to Intro (0s), 125s is an exact match for Topic A,
# and 900s is far from everything but still closest to Closing (600s, diff
# 300) rather than Topic B (340s, diff 560).
my @selected = select_moment_texts(\@moments, [900, 2, 125]);

is(scalar(@selected), 3, "returns one entry per selected timestamp");
is($selected[0]{text}, "Intro", "sorted ascending: Intro (0s) comes first");
is($selected[0]{timestamp_seconds}, 0, "target 2s snaps to Intro's own timestamp (0s), not the input");
is($selected[1]{text}, "Topic A", "target 125s matches Topic A exactly");
is($selected[2]{text}, "Closing", "target 900s snaps to the closest moment, Closing (600s), not Topic B (340s)");

done_testing();
