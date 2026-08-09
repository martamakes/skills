use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

require "$RealBin/../yt-to-webpage.pl";

is(seconds_to_filename(0), "00-00-00", "zero seconds");
is(seconds_to_filename(65), "00-01-05", "one minute five seconds");
is(seconds_to_filename(3725), "01-02-05", "one hour two minutes five seconds");

is(escape_html("<script>alert(1)</script>"), "&lt;script&gt;alert(1)&lt;/script&gt;",
    "escapes angle brackets");
is(escape_html("Tom & Jerry"), "Tom &amp; Jerry", "escapes ampersand");

my @selected = (
    { timestamp_seconds => 65, text => "Topic <A> & stuff" },
);
my $html = generate_html(\@selected, "https://www.youtube.com/watch?v=abc123");

like($html, qr/<h1>Youtube transcript</, "has the fixed English title");
like($html, qr{Source: <a href="https://www\.youtube\.com/watch\?v=abc123"}, "links the source url");
like($html, qr{images/00-01-05\.jpg}, "references the correctly-named screenshot");
like($html, qr{Topic &lt;A&gt; &amp; stuff}, "transcript text is escaped in the output");
like($html, qr{href="https://www\.youtube\.com/watch\?v=abc123&t=65"}, "deep link includes seconds");

done_testing();
