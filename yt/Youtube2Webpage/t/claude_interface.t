use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

require "$RealBin/../yt-to-webpage.pl";

# --- build_claude_prompt ---
my $prompt = build_claude_prompt("[0] hello\n[10] world\n");
like($prompt, qr/JSON array of integers/, "prompt asks for a JSON array of integers");
like($prompt, qr/\[0\] hello/, "prompt embeds the transcript text");
like($prompt, qr/new sub-topic|new piece of content/, "prompt describes what a key moment is");

# --- parse_claude_response: happy path ---
my @ts = parse_claude_response('{"result":"[125,340,812]"}');
is_deeply(\@ts, [125, 340, 812], "extracts array from clean JSON result");

# --- parse_claude_response: extra prose around the array ---
@ts = parse_claude_response('{"result":"Here are the moments: [125, 340] Hope that helps!"}');
is_deeply(\@ts, [125, 340], "extracts array even with prose around it");

# --- parse_claude_response: error cases ---
eval { parse_claude_response('not json at all') };
like($@, qr/did not return valid JSON/, "dies on invalid outer JSON");

eval { parse_claude_response('{"no_result_field":true}') };
like($@, qr/no 'result' field/, "dies when result field is missing");

eval { parse_claude_response('{"result":"no array here"}') };
like($@, qr/Could not find a JSON array/, "dies when no array is present in result");

eval { parse_claude_response('{"result":"[]"}') };
like($@, qr/zero key moments/, "dies on empty array");

done_testing();
