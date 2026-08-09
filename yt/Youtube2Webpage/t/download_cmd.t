use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

require "$RealBin/../yt-to-webpage.pl";

# --- prompt_subtitle_language ---
open(my $fh, "<", \"es\n") or die $!;
is(prompt_subtitle_language($fh), "es", "reads the language from the given filehandle");
close $fh;

open(my $empty_fh, "<", \"") or die $!;
is(prompt_subtitle_language($empty_fh), "en", "defaults to en on empty input");
close $empty_fh;

# --- build_ytdlp_cmd ---
my @cmd = build_ytdlp_cmd("https://www.youtube.com/watch?v=abc123", "es");
is($cmd[0], "yt-dlp", "first arg is the yt-dlp binary");
ok((grep { $_ eq "chrome" } @cmd), "includes chrome as the cookies browser");
ok((grep { $_ eq "--cookies-from-browser" } @cmd), "includes the cookies flag");
ok((grep { $_ eq "bv*[height<=720]+ba/b[height<=720]" } @cmd), "caps quality at 720p");
ok((grep { $_ eq "--sub-lang" } @cmd), "includes explicit sub-lang flag");
ok((grep { $_ eq "es" } @cmd), "passes through the requested language");
is($cmd[-1], "https://www.youtube.com/watch?v=abc123", "url is the last argument");

done_testing();
