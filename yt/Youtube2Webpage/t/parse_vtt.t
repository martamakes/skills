use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempfile);

require "$RealBin/../yt-to-webpage.pl";

# --- timestamp_to_seconds ---
is(timestamp_to_seconds("00:00:05.000"), 5, "seconds only");
is(timestamp_to_seconds("00:02:05.500"), 125, "minutes + seconds");
is(timestamp_to_seconds("01:02:05.500"), 3725, "hours + minutes + seconds");
eval { timestamp_to_seconds("not-a-timestamp") };
like($@, qr/Invalid timestamp format/, "dies on bad format");

# --- parse_vtt ---
my $vtt_content = <<'VTT';
WEBVTT
Kind: captions
Language: en

00:00:00.000 --> 00:00:02.000
Hello and welcome<00:00:00.500><c> everyone</c>

00:00:02.000 --> 00:00:04.000
Hello and welcome everyone
to this talk about Perl

00:00:04.000 --> 00:00:06.000
to this talk about Perl

00:00:06.000 --> 00:00:08.000
Let's get started
VTT

my ($fh, $filename) = tempfile(SUFFIX => '.vtt');
print $fh $vtt_content;
close $fh;

my @moments = parse_vtt($filename);
is(scalar(@moments), 3, "duplicate consecutive lines collapsed to 3 unique moments");
is($moments[0]{text}, "Hello and welcome everyone", "first moment text (no <c> tag line kept)");
is($moments[0]{timestamp}, "00:00:02.000", "first moment timestamp is the one attached to the kept line");
is($moments[1]{text}, "to this talk about Perl", "second moment text");
is($moments[2]{text}, "Let's get started", "third moment text");

unlink $filename;

done_testing();
