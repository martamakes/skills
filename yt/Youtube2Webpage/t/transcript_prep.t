use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

require "$RealBin/../yt-to-webpage.pl";

my @moments = (
    { timestamp => "00:00:02.000", text => "Hello and welcome everyone" },
    { timestamp => "00:02:05.500", text => "to this talk about Perl" },
);

my $text = build_transcript_text(\@moments);
is($text, "[2] Hello and welcome everyone\n[125] to this talk about Perl\n",
    "formats each moment as [seconds] text");

ok(check_transcript_size("short text"), "under limit returns true");

my $huge = "x" x 500_001;
eval { check_transcript_size($huge) };
like($@, qr/Transcript too large.*500001 characters/,
    "dies with size in the message when over the 500K limit");

my $exact = "x" x 500_000;
ok(check_transcript_size($exact), "exactly at the limit is allowed");

done_testing();
