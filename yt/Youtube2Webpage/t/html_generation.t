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

# --- youtube source: link is the url itself ---
my $youtube_html = generate_html(\@selected,
    { label => "https://www.youtube.com/watch?v=abc123", link => "https://www.youtube.com/watch?v=abc123" });

like($youtube_html, qr/<h1>Video transcript</, "has the fixed generic title");
like($youtube_html, qr{Source: <a href="https://www\.youtube\.com/watch\?v=abc123"},
    "links the source url");
like($youtube_html, qr{images/00-01-05\.jpg}, "references the correctly-named screenshot");
like($youtube_html, qr{Topic &lt;A&gt; &amp; stuff}, "transcript text is escaped in the output");
like($youtube_html, qr{href="https://www\.youtube\.com/watch\?v=abc123&t=65"}, "deep link includes seconds");

# --- local source: no link, filename shown as plain text ---
my $local_html = generate_html(\@selected,
    { label => "My Documentary.mov", link => undef });

like($local_html, qr/<h1>Video transcript</, "local mode has the same fixed title");
like($local_html, qr{Source: My Documentary\.mov(?!</a>)}, "source is plain text, not a link");
unlike($local_html, qr{<a href="[^"]*"[^>]*>My Documentary\.mov</a>}, "source is not wrapped in a link");
unlike($local_html, qr{class="videolink"}, "no per-moment videolink when there is no link");
like($local_html, qr{images/00-01-05\.jpg}, "still references the screenshot in local mode");

done_testing();
