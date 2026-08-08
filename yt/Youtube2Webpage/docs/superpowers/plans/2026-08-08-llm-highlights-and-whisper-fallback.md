# Youtube2Webpage v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `yt-to-webpage.pl` so it captures one screenshot per **Momento
clave** (LLM-identified topic change) instead of one per subtitle line, falls
back to local Whisper transcription when no captions exist, and applies the
robustness fixes (quality cap, cookies, exit-code checks) agreed in the spec.

**Architecture:** Single Perl script, refactored into small testable subs
(`parse_vtt`, `build_claude_prompt`, `parse_claude_response`,
`select_moment_texts`, `generate_html`, etc.) plus a thin `run()` orchestrator
that wires them together with the actual I/O (yt-dlp, whisper, claude, ffmpeg
subprocess calls). The script stays loadable via `require` (guarded by
`run() unless caller();`) so pure-logic subs get real `Test::More` unit tests,
while I/O-heavy orchestration is validated end-to-end manually, per the
testing approach agreed in the spec.

**Tech Stack:** Perl 5.34 (`Test::More`, `JSON::PP`, `IPC::Open2`, `FindBin` —
all core modules, no new CPAN dependencies), `yt-dlp`, `ffmpeg`, `whisper`
(openai-whisper, `turbo` model), `claude` CLI.

**Spec:** [2026-08-08-llm-highlights-and-language-design.md](../specs/2026-08-08-llm-highlights-and-language-design.md)
**Domain terms:** [CONTEXT.md](../../../CONTEXT.md)

## Global Constraints

- Video quality cap: `-f "bv*[height<=720]+ba/b[height<=720]"` (720p)
- yt-dlp auth/rate-limit: `--cookies-from-browser chrome`, `--sleep-requests 1`
- Whisper fallback: model `turbo`, `--output_format vtt`, no `--language` flag
  (auto-detection)
- Single-call transcript size limit: 500,000 characters. Above this, abort
  with a clear message — no chunking/windowing is implemented in this plan.
- Claude invocation: `claude -p --output-format json`, prompt piped via STDIN.
  No `--bare` (would require a separate `ANTHROPIC_API_KEY`, out of scope).
- Interface strings (`<h1>Youtube transcript</h1>`, "Source:", etc.) are fixed
  in English. No translation, no localization logic.
- The LLM only ever returns timestamps (JSON array of integers). It never
  generates or rewrites transcript text — displayed text is always a literal
  quote pulled from the parsed `.vtt`.
- No minimum-gap guardrail between consecutive key moments (YAGNI, per spec).

---

## File Structure

- **Modify:** `yt-to-webpage.pl` — refactor the existing inline script into
  named subs (listed below) plus a `run()` orchestrator, guarded by
  `run() unless caller();` and ending in `1;` so it stays `require`-able from
  tests without executing.
- **Create:** `t/parse_vtt.t` — tests for `timestamp_to_seconds`, `parse_vtt`
- **Create:** `t/transcript_prep.t` — tests for `build_transcript_text`,
  `check_transcript_size`
- **Create:** `t/claude_interface.t` — tests for `build_claude_prompt`,
  `parse_claude_response`
- **Create:** `t/moment_matching.t` — tests for `select_moment_texts`
- **Create:** `t/html_generation.t` — tests for `seconds_to_filename`,
  `escape_html`, `generate_html`
- **Create:** `t/download_cmd.t` — tests for `prompt_subtitle_language`,
  `build_ytdlp_cmd`
- **Create:** `t/whisper_fallback.t` — tests for `has_vtt_files`,
  `build_whisper_cmd`
- **Create:** `t/ffmpeg_cmd.t` — tests for `build_ffmpeg_cmd`
- **Create:** `t/io_wrappers.t` — tests for the 4 error-checking I/O wrapper
  subs (`run_ytdlp`, `run_whisper`, `invoke_claude_cli`,
  `run_ffmpeg_capture`), using fake executables on `PATH` to simulate success
  and failure without calling the real tools
- **Modify:** `README.md` — document the new interactive prompt, the Whisper
  fallback, and the new dependencies (`whisper`, `claude` CLI, Chrome cookies)

No new files needed for `run()` itself — it stays in `yt-to-webpage.pl` and is
validated manually (Task 10), per the spec's testing approach: this is a
personal script wrapping external tools, so pure logic gets unit tests and
orchestration gets an end-to-end smoke test.

---

### Task 1: Parsing subsystem — `timestamp_to_seconds`, `parse_vtt`

**Files:**
- Modify: `yt-to-webpage.pl` (replace the inline `while (my $line = <$fh>)`
  parsing loop with these two subs; add the `require`-able guard)
- Test: `t/parse_vtt.t`

**Interfaces:**
- Produces: `timestamp_to_seconds($ts_string)` → integer seconds. Dies with
  `"Invalid timestamp format: $ts"` on bad input.
- Produces: `parse_vtt($vtt_path)` → list of hashrefs
  `{ timestamp => "HH:MM:SS.mmm", text => "..." }`, in chronological order,
  with consecutive duplicate text lines collapsed (same dedupe behavior as
  the current script).

- [ ] **Step 1: Write the failing tests**

```perl
# t/parse_vtt.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/parse_vtt.t`
Expected: FAIL — `Undefined subroutine &main::timestamp_to_seconds called`
(the subs don't exist yet, and the script isn't `require`-able yet)

- [ ] **Step 3: Make the script require-able and add the two subs**

At the very top of `yt-to-webpage.pl`, keep the existing `use warnings; use
strict; use autodie;` lines. Replace everything from `my $slug = shift @ARGV;`
down to (and including) the old inline parsing `while` loop and `gen_images`
sub with the following — this moves the old top-level code into a `run()` sub
(built out fully in Task 9) and adds the two new subs:

```perl
sub timestamp_to_seconds {
    my ($ts) = @_;
    if ($ts =~ /^(\d+):(\d+):(\d+)(?:\.\d+)?$/) {
        return $1 * 3600 + $2 * 60 + $3;
    }
    die "Invalid timestamp format: $ts";
}

sub parse_vtt {
    my ($vtt_path) = @_;
    open(my $fh, "<", $vtt_path);
    my $timestamp_seen = 0;
    my $this_start = 0;
    my $last_text_line = '';
    my @moments;
    while (my $line = <$fh>) {
        chomp $line;
        if (!$timestamp_seen) {
            if ($line =~ /^\d\d:\d\d/) {
                $timestamp_seen = 1;
            } else {
                next;
            }
        }
        next if $line =~ /^\s*$/;
        next if $line =~ /<\/c>$/;
        if ($line =~ /(\d\d:\d\d:\d\d\.\d\d\d) --> (\d\d:\d\d:\d\d\.\d\d\d)/) {
            $this_start = $1;
            next;
        }
        next if $line eq $last_text_line;
        push @moments, { timestamp => $this_start, text => $line };
        $last_text_line = $line;
    }
    close $fh;
    return @moments;
}

1;
```

Leave a placeholder `sub run { }` and `run() unless caller();` at the very
end of the file for now — it gets filled in fully in Task 9. The file must
end in `1;` (after the `run() unless caller();` line) so `require` succeeds
from test files.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/parse_vtt.t`
Expected: PASS — all 8 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/parse_vtt.t
git commit -m "refactor(yt): extract timestamp_to_seconds and parse_vtt as testable subs"
```

---

### Task 2: Transcript prep — `build_transcript_text`, `check_transcript_size`

**Files:**
- Modify: `yt-to-webpage.pl`
- Test: `t/transcript_prep.t`

**Interfaces:**
- Consumes: `timestamp_to_seconds($ts_string)` from Task 1.
- Produces: `build_transcript_text($moments_arrayref)` → string, one line per
  moment formatted as `"[<seconds>] <text>\n"`.
- Produces: `check_transcript_size($text)` → returns `1` if
  `length($text) <= 500_000`; dies with
  `"Transcript too large to analyze in a single call (<N> characters, limit 500000). Chunking is not implemented yet.\n"`
  otherwise.

- [ ] **Step 1: Write the failing tests**

```perl
# t/transcript_prep.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/transcript_prep.t`
Expected: FAIL — `Undefined subroutine &main::build_transcript_text called`

- [ ] **Step 3: Implement the two subs**

Add above the `1;` line in `yt-to-webpage.pl` (after `parse_vtt`):

```perl
sub build_transcript_text {
    my ($moments) = @_;
    my $text = '';
    foreach my $m (@$moments) {
        my $seconds = timestamp_to_seconds($m->{timestamp});
        $text .= "[$seconds] $m->{text}\n";
    }
    return $text;
}

sub check_transcript_size {
    my ($text) = @_;
    my $len = length($text);
    if ($len > 500_000) {
        die "Transcript too large to analyze in a single call ($len characters, limit 500000). Chunking is not implemented yet.\n";
    }
    return 1;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/transcript_prep.t`
Expected: PASS — all 4 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/transcript_prep.t
git commit -m "feat(yt): add build_transcript_text and 500K-char size guard"
```

---

### Task 3: LLM interface — `build_claude_prompt`, `parse_claude_response`

**Files:**
- Modify: `yt-to-webpage.pl` (add `use JSON::PP qw(decode_json);` near the
  top, alongside the existing `use` lines)
- Test: `t/claude_interface.t`

**Interfaces:**
- Produces: `build_claude_prompt($transcript_text)` → string prompt asking
  for a JSON array of integer second-offsets marking key moments (topic
  changes), with an example and the transcript embedded.
- Produces: `parse_claude_response($raw_claude_stdout)` → list of integers
  (ascending timestamps in seconds). Dies with a descriptive message
  (including the raw output) if: the outer JSON doesn't parse, there's no
  `result` field, no `[...]` array can be found inside `result`, the array
  itself doesn't parse, or the array is empty.

- [ ] **Step 1: Write the failing tests**

```perl
# t/claude_interface.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/claude_interface.t`
Expected: FAIL — `Undefined subroutine &main::build_claude_prompt called`

- [ ] **Step 3: Implement the two subs**

Add `use JSON::PP qw(decode_json);` next to the existing `use strict;` /
`use warnings;` lines at the top of `yt-to-webpage.pl`. Then add above `1;`:

```perl
sub build_claude_prompt {
    my ($transcript_text) = @_;
    return <<"PROMPT";
You are analyzing a video transcript. Each line is formatted as "[seconds] text",
where "seconds" is the timestamp in the video where that line starts.

Identify the KEY MOMENTS in this transcript: points where the speaker moves to a
new sub-topic or starts a new piece of content (a new concept, a new demo, a new
example). Do NOT select standalone quotes or remarks within the same topic block.

Respond with ONLY a JSON array of integers - the "seconds" value of each key
moment, in ascending order. No explanation, no markdown, no extra text.

Example response: [125, 340, 812, 1290]

Transcript:
$transcript_text
PROMPT
}

sub parse_claude_response {
    my ($raw_output) = @_;
    my $outer;
    eval { $outer = decode_json($raw_output); };
    die "Claude CLI did not return valid JSON wrapper: $@\nRaw output:\n$raw_output\n" if $@;

    my $result_text = $outer->{result};
    die "Claude CLI response has no 'result' field.\nRaw output:\n$raw_output\n"
        unless defined $result_text;

    unless ($result_text =~ /(\[.*\])/s) {
        die "Could not find a JSON array in Claude's response.\nResponse text:\n$result_text\n";
    }
    my $array_text = $1;

    my $timestamps;
    eval { $timestamps = decode_json($array_text); };
    die "Claude's JSON array did not parse: $@\nArray text:\n$array_text\n" if $@;

    die "Claude returned zero key moments.\n" unless @$timestamps;

    for my $t (@$timestamps) {
        die "Claude returned a non-numeric timestamp: '$t'\n" unless $t =~ /^\d+(?:\.\d+)?$/;
    }

    return @$timestamps;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/claude_interface.t`
Expected: PASS — all 9 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/claude_interface.t
git commit -m "feat(yt): add build_claude_prompt and tolerant parse_claude_response"
```

---

### Task 4: Moment matching — `select_moment_texts`

**Files:**
- Modify: `yt-to-webpage.pl`
- Test: `t/moment_matching.t`

**Interfaces:**
- Consumes: `timestamp_to_seconds($ts_string)` from Task 1.
- Produces: `select_moment_texts($moments_arrayref, $selected_timestamps_arrayref)`
  → list of hashrefs `{ timestamp_seconds => INT, text => STRING }`, sorted
  ascending by `timestamp_seconds`. For each selected timestamp, picks the
  moment whose own timestamp (converted to seconds) is numerically closest.

- [ ] **Step 1: Write the failing test**

```perl
# t/moment_matching.t
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/moment_matching.t`
Expected: FAIL — `Undefined subroutine &main::select_moment_texts called`

- [ ] **Step 3: Implement the sub**

Add above `1;`:

```perl
sub select_moment_texts {
    my ($all_moments, $selected_timestamps) = @_;
    my @selected;
    foreach my $target (@$selected_timestamps) {
        my $best;
        my $best_diff;
        foreach my $m (@$all_moments) {
            my $seconds = timestamp_to_seconds($m->{timestamp});
            my $diff = abs($seconds - $target);
            if (!defined $best_diff || $diff < $best_diff) {
                $best_diff = $diff;
                $best = { timestamp_seconds => $seconds, text => $m->{text} };
            }
        }
        push @selected, $best if $best;
    }
    @selected = sort { $a->{timestamp_seconds} <=> $b->{timestamp_seconds} } @selected;
    return @selected;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/moment_matching.t`
Expected: PASS — all 5 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/moment_matching.t
git commit -m "feat(yt): add select_moment_texts (nearest-timestamp matching)"
```

---

### Task 5: HTML rendering — `seconds_to_filename`, `escape_html`, `generate_html`

**Files:**
- Modify: `yt-to-webpage.pl`
- Test: `t/html_generation.t`

**Interfaces:**
- Produces: `seconds_to_filename($seconds)` → `"HH-MM-SS"` zero-padded string.
- Produces: `escape_html($text)` → string with `&`, `<`, `>` escaped.
- Produces: `generate_html($selected_moments_arrayref, $url)` → full HTML
  string. Interface text fixed in English. Each moment renders an `<li>`
  with `images/<seconds_to_filename>.jpg`, the escaped literal text, and a
  link to `$url&t=<seconds>`.

- [ ] **Step 1: Write the failing tests**

```perl
# t/html_generation.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/html_generation.t`
Expected: FAIL — `Undefined subroutine &main::seconds_to_filename called`

- [ ] **Step 3: Implement the three subs**

Add above `1;`:

```perl
sub seconds_to_filename {
    my ($seconds) = @_;
    my $h = int($seconds / 3600);
    my $m = int(($seconds % 3600) / 60);
    my $s = $seconds % 60;
    return sprintf("%02d-%02d-%02d", $h, $m, $s);
}

sub escape_html {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

sub generate_html {
    my ($selected, $url) = @_;
    my $html = <<"HEADER";
<html>
<head>
 <link rel="stylesheet" type="text/css" href="styles.css" />
</head>
<body>

<h1>Youtube transcript</h1>
Source: <a href="$url" target="_blank">$url</a>

<ul>
HEADER
    foreach my $m (@$selected) {
        my $seconds = $m->{timestamp_seconds};
        my $ts_filename = seconds_to_filename($seconds);
        my $escaped_text = escape_html($m->{text});
        $html .= qq{<li>
	<div class="grab"><img src="images/$ts_filename.jpg" /></div><div class="subtitle"><span id="$seconds">$escaped_text</span>
<a href="${url}&t=${seconds}" target="blank" class="videolink">#</a>
	</div></li>\n};
    }
    $html .= "\n</ul>\n</body>\n</html>";
    return $html;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/html_generation.t`
Expected: PASS — all 10 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/html_generation.t
git commit -m "feat(yt): add generate_html with escaping (fixed English interface)"
```

---

### Task 6: Download subsystem — `prompt_subtitle_language`, `build_ytdlp_cmd`

**Files:**
- Modify: `yt-to-webpage.pl`
- Test: `t/download_cmd.t`

**Interfaces:**
- Produces: `prompt_subtitle_language($optional_input_filehandle)` → language
  code string. Prompts on STDOUT, reads one line from the given filehandle
  (defaults to `\*STDIN`). Defaults to `"en"` if the input is empty/EOF.
- Produces: `build_ytdlp_cmd($url, $lang)` → list of command-line arguments
  (list form, no shell interpolation) implementing the 720p cap, Chrome
  cookies, sleep, explicit `--sub-lang`, and `--print filename`.

- [ ] **Step 1: Write the failing tests**

```perl
# t/download_cmd.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/download_cmd.t`
Expected: FAIL — `Undefined subroutine &main::prompt_subtitle_language called`

- [ ] **Step 3: Implement the two subs**

Add above `1;`:

```perl
sub prompt_subtitle_language {
    my ($in_fh) = @_;
    $in_fh //= \*STDIN;
    print "Preferred subtitle language (e.g. en, es) [en]: ";
    my $answer = <$in_fh>;
    chomp $answer if defined $answer;
    $answer = 'en' unless defined $answer && length $answer;
    return $answer;
}

sub build_ytdlp_cmd {
    my ($url, $lang) = @_;
    return (
        'yt-dlp',
        '--cookies-from-browser', 'chrome',
        '--sleep-requests', '1',
        '-f', 'bv*[height<=720]+ba/b[height<=720]',
        '--write-auto-subs', '--write-subs',
        '--sub-lang', $lang,
        '--print', 'filename',
        '--no-simulate',
        $url,
    );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/download_cmd.t`
Expected: PASS — all 9 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/download_cmd.t
git commit -m "feat(yt): add prompt_subtitle_language and build_ytdlp_cmd (720p, cookies, sleep)"
```

---

### Task 7: Whisper fallback — `has_vtt_files`, `build_whisper_cmd`

**Files:**
- Modify: `yt-to-webpage.pl`
- Test: `t/whisper_fallback.t`

**Interfaces:**
- Produces: `has_vtt_files($dir)` → true/false, whether `$dir` contains at
  least one `*.vtt` file.
- Produces: `build_whisper_cmd($video_file)` → list of command-line
  arguments: `whisper`, the video file, `--model turbo`,
  `--output_format vtt`, no `--language` (auto-detect).

- [ ] **Step 1: Write the failing tests**

```perl
# t/whisper_fallback.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/whisper_fallback.t`
Expected: FAIL — `Undefined subroutine &main::has_vtt_files called`

- [ ] **Step 3: Implement the two subs**

Add above `1;`:

```perl
sub has_vtt_files {
    my ($dir) = @_;
    opendir(my $dh, $dir);
    my @vtts = grep { /\.vtt$/ } readdir($dh);
    closedir $dh;
    return scalar(@vtts) > 0;
}

sub build_whisper_cmd {
    my ($video_file) = @_;
    return ('whisper', $video_file, '--model', 'turbo', '--output_format', 'vtt');
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/whisper_fallback.t`
Expected: PASS — all 3 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/whisper_fallback.t
git commit -m "feat(yt): add has_vtt_files and build_whisper_cmd for the Whisper fallback"
```

---

### Task 8: Screenshot capture command — `build_ffmpeg_cmd`

**Files:**
- Modify: `yt-to-webpage.pl`
- Test: `t/ffmpeg_cmd.t`

**Interfaces:**
- Produces: `build_ffmpeg_cmd($seconds, $video_file, $output_path)` → list of
  command-line arguments for a single-frame capture at `$seconds`, scaled to
  1024px wide, written to `$output_path`.

- [ ] **Step 1: Write the failing test**

```perl
# t/ffmpeg_cmd.t
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/ffmpeg_cmd.t`
Expected: FAIL — `Undefined subroutine &main::build_ffmpeg_cmd called`

- [ ] **Step 3: Implement the sub**

Add above `1;`:

```perl
sub build_ffmpeg_cmd {
    my ($seconds, $video_file, $output_path) = @_;
    return (
        'ffmpeg', '-ss', $seconds, '-nostdin', '-i', $video_file,
        '-frames:v', '1', '-q:v', '2', '-vf', 'scale=1024:-1',
        $output_path,
    );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/ffmpeg_cmd.t`
Expected: PASS — 1 assertion green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/ffmpeg_cmd.t
git commit -m "feat(yt): add build_ffmpeg_cmd for per-moment screenshot capture"
```

---

### Task 9: I/O wrapper subs with error-path tests

**Files:**
- Modify: `yt-to-webpage.pl` (add `use IPC::Open2;` next to the other `use`
  lines; add the 4 wrapper subs above `1;`)
- Test: `t/io_wrappers.t`

**Interfaces:**
- Produces: `run_ytdlp(@cmd)` → captured stdout string on success (exit 0);
  dies with `"yt-dlp exited with status <N>.\nOutput:\n<output>\n"` otherwise.
- Produces: `run_whisper(@cmd)` → `1` on success; dies with
  `"whisper exited with status <N> while transcribing audio.\n"` otherwise.
- Produces: `invoke_claude_cli($prompt)` → captured stdout string on success;
  dies with `"claude CLI exited with status <N>.\nOutput:\n<output>\n"`
  otherwise. Writes `$prompt` to the child's STDIN.
- Produces: `run_ffmpeg_capture(@cmd)` → true/false (never dies) — a single
  failed screenshot must not abort the whole run, per the spec's error table.

These wrappers only differ from a plain `system(@cmd)` call in *how they
react to a non-zero exit code* — that reaction is exactly what the spec's
error table demands, and it is fully testable without touching the network,
a real video file, or a real LLM: fake executables on `PATH` stand in for
`yt-dlp`/`whisper`/`claude`/`ffmpeg` and simply exit with a controlled code.

- [ ] **Step 1: Write the failing tests**

```perl
# t/io_wrappers.t
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/io_wrappers.t`
Expected: FAIL — `Undefined subroutine &main::run_ytdlp called`

- [ ] **Step 3: Implement the 4 wrapper subs**

Add `use IPC::Open2;` next to the existing `use` lines at the top of
`yt-to-webpage.pl`. Add these subs above `1;`:

```perl
sub run_ytdlp {
    my (@cmd) = @_;
    open(my $ph, "-|", @cmd) or die "Failed to run yt-dlp: $!\n";
    my $output = do { local $/; <$ph> };
    close $ph;
    my $exit = $? >> 8;
    if ($exit != 0) {
        die "yt-dlp exited with status $exit.\nOutput:\n$output\n";
    }
    return $output;
}

sub run_whisper {
    my (@cmd) = @_;
    system(@cmd);
    my $exit = $? >> 8;
    if ($exit != 0) {
        die "whisper exited with status $exit while transcribing audio.\n";
    }
    return 1;
}

sub run_ffmpeg_capture {
    my (@cmd) = @_;
    system(@cmd);
    my $exit = $? >> 8;
    return $exit == 0;
}

sub invoke_claude_cli {
    my ($prompt) = @_;
    my ($reader, $writer);
    my $pid = open2($reader, $writer, 'claude', '-p', '--output-format', 'json');
    print $writer $prompt;
    close $writer;
    my $output = do { local $/; <$reader> };
    close $reader;
    waitpid($pid, 0);
    my $exit = $? >> 8;
    if ($exit != 0) {
        die "claude CLI exited with status $exit.\nOutput:\n$output\n";
    }
    return $output;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -v t/io_wrappers.t`
Expected: PASS — all 8 assertions green

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/io_wrappers.t
git commit -m "feat(yt): add I/O wrapper subs with fake-executable error-path tests"
```

---

### Task 10: Wire up `run()` — full orchestration

**Files:**
- Modify: `yt-to-webpage.pl` (replace the placeholder `sub run { }` from
  Task 1 with the full implementation)

**Interfaces:**
- Consumes every sub produced in Tasks 1-9 (`run_ytdlp`, `run_whisper`,
  `invoke_claude_cli`, `run_ffmpeg_capture` are already implemented and
  tested — this task only calls them).
- Produces: `run()` — no return value relied upon; side effects are the
  generated `project-name/` directory with `index.html`, `images/`, and the
  downloaded video/vtt files.

This task is orchestration glue around already-tested functions (both the
pure ones from Tasks 1-8 and the error-checked I/O wrappers from Task 9), so
it is validated end-to-end in Task 11 rather than with new unit tests.

- [ ] **Step 1: Replace the placeholder `run()` with the full orchestrator**

```perl
sub run {
    my $slug = shift @ARGV;
    my $url = shift @ARGV;

    if (!$url || $url !~ m|^https://www\.youtube\.com|) {
        print STDERR "Usage:\n";
        print STDERR "$0 project-name \"https://www.youtube.com/watch?v=jNQXAC9IVRw\"\n";
        exit 1;
    }

    mkdir($slug) unless -d $slug;
    chdir($slug);

    my $lang = prompt_subtitle_language();

    my @ytdlp_cmd = build_ytdlp_cmd($url, $lang);
    my $ytdlp_output = run_ytdlp(@ytdlp_cmd);
    (my $video_file = $ytdlp_output) =~ s/\s+\z//;

    unless (has_vtt_files('.')) {
        print STDERR "No subtitles found for this video. Falling back to local Whisper transcription...\n";
        my @whisper_cmd = build_whisper_cmd($video_file);
        run_whisper(@whisper_cmd);
        unless (has_vtt_files('.')) {
            die "Whisper did not produce a .vtt file. Aborting.\n";
        }
    }

    my ($vtt_path) = glob('*.vtt');
    die "No .vtt file available after download/transcription.\n" unless $vtt_path;

    my @moments = parse_vtt($vtt_path);
    die "Transcript is empty after parsing $vtt_path.\n" unless @moments;

    my $transcript_text = build_transcript_text(\@moments);
    check_transcript_size($transcript_text);

    my $prompt = build_claude_prompt($transcript_text);
    my $claude_output = invoke_claude_cli($prompt);
    my @selected_timestamps = parse_claude_response($claude_output);

    my @selected_moments = select_moment_texts(\@moments, \@selected_timestamps);

    mkdir('images') unless -d 'images';
    foreach my $m (@selected_moments) {
        my $ts_filename = seconds_to_filename($m->{timestamp_seconds});
        my $image_path = "images/$ts_filename.jpg";
        my @ffmpeg_cmd = build_ffmpeg_cmd($m->{timestamp_seconds}, $video_file, $image_path);
        my $ok = run_ffmpeg_capture(@ffmpeg_cmd);
        unless ($ok) {
            print STDERR "Warning: failed to capture screenshot at $m->{timestamp_seconds}s, skipping.\n";
        }
    }

    system('cp', '../styles.css', '.') if -f '../styles.css';

    my $html = generate_html(\@selected_moments, $url);
    open(my $out, '>', 'index.html');
    print $out $html;
    close $out;

    print "Done. Open index.html in $slug/ to view the result.\n";
}

run() unless caller();
1;
```

- [ ] **Step 2: Run the full existing test suite to confirm nothing broke**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -lv t/`
Expected: PASS — all 9 test files green (Tasks 1-9's tests still pass; `run()`
itself has no unit tests, by design, per the spec's testing approach — its
building blocks, including the error-checking wrappers, are already covered)

- [ ] **Step 3: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl
git commit -m "feat(yt): wire up run() orchestration (whisper fallback, LLM moment selection, error handling)"
```

---

### Task 11: End-to-end validation + README update

**Files:**
- Modify: `README.md`

This task has no new automated tests — it is the manual end-to-end
validation the spec's testing section calls for (the happy path and the
Whisper fallback path specifically — the 4 hard failure paths are already
covered by Task 9's automated tests), plus documenting the new behavior for
future-you.

- [ ] **Step 1: Run the full unit test suite one more time**

Run: `cd /Volumes/BIWIN/skills/yt/Youtube2Webpage && prove -lv t/`
Expected: PASS — all 9 test files green

- [ ] **Step 2: Validate end-to-end against the short example video**

```bash
cd /Volumes/BIWIN/skills/yt/Youtube2Webpage
rm -rf example
perl yt-to-webpage.pl example "https://www.youtube.com/watch?v=jNQXAC9IVRw"
```

When prompted, type `en` and press Enter.

Expected: completes without errors, prints
`Done. Open index.html in example/ to view the result.`, and
`example/index.html` + `example/images/*.jpg` exist with more than zero
images and no HTML-escaping artifacts in the visible text.

- [ ] **Step 3: Validate the Whisper fallback path**

Pick any short (1-2 min) YouTube video you know has no captions available
(check first with `yt-dlp --list-subs "URL"` — an empty list confirms it),
then run the script against it the same way. Confirm in the output that you
see `"No subtitles found for this video. Falling back to local Whisper
transcription..."` and that the run still completes and produces a
non-empty `index.html`.

- [ ] **Step 4: Update README.md**

Read the current `README.md` first, then update the "Using" and "Dependencies"
sections to reflect: the new interactive subtitle-language prompt, the new
`whisper` and `claude` CLI dependencies, and the Whisper fallback behavior.
Keep the existing structure and tone of the file; add rather than rewrite.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/README.md
git commit -m "docs(yt): document subtitle-language prompt, whisper fallback and new deps"
```

---

## Self-Review Notes

- **Spec coverage:** Momento clave selection (Tasks 1-4, 10), Whisper
  fallback (Tasks 7, 9, 10), single-call 500K limit with no chunking (Tasks
  2, 10), the 5 robustness fixes — quality cap/cookies/exit-codes/sub-lang/
  per-moment capture (Tasks 6, 8, 10) — and every row of the spec's
  error-handling table are covered: the 4 rows that are hard failures owned
  by an I/O wrapper (`yt-dlp`/`whisper`/`claude` failing, or an unparseable
  JSON response) are unit-tested in Task 9 with fake executables; the "no
  subtitles at all" and "zero moments returned" rows are exercised by
  `run()`'s own logic (Task 10) and the manual Whisper-fallback check
  (Task 11); the one non-fatal row (a single `ffmpeg` capture failing) is
  unit-tested in Task 9 (`run_ffmpeg_capture` returns false without dying)
  and wired as a warn-and-continue in Task 10. Non-goals (no translation, no
  windowing, fixed English interface) are respected — no code for any of
  them exists in this plan.
- **Claude invocation mode:** uses plain `claude -p --output-format json`
  (not `--bare`), per the explicit choice made during planning — cheaper
  `--bare` path is a known future option if `ANTHROPIC_API_KEY` gets set up.
- **Grilled 2026-08-08:** added Task 9 (I/O wrapper error-path tests) after
  noticing the plan had no automated coverage — and only two of the seven
  error-table rows even covered manually — for exactly the failure modes the
  original script mishandled silently. Also caught and fixed a wrong
  expectation in Task 4's `select_moment_texts` test: manually tracing the
  nearest-match logic against the original `[341, 125, 900]` input showed
  "Intro" (0s) is never selected — the assertions claimed it was.
