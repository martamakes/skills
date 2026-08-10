# Local Video Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `yt-to-webpage.pl` accept a local video file path as a second, permanent input mode alongside YouTube URLs, reusing the existing transcript/Claude/screenshot pipeline unchanged.

**Architecture:** A new pure function `classify_video_source($arg)` replaces the current inline YouTube-URL regex check in `run()`, returning a tagged hash (`youtube` / `local` / `invalid_extension` / `undef`). `run()` branches on the tag to skip yt-dlp and the subtitle-language prompt in local mode (the existing Whisper fallback then triggers naturally). `generate_html()`'s second parameter becomes a `{ label, link }` hash instead of a bare URL string, so it can render a plain filename with no clickable link for local sources.

**Tech Stack:** Perl (`strict`, `warnings`, `autodie`), `Test::More`, `File::Temp`, `Cwd`, `File::Basename` — all core modules, no new dependencies.

## Global Constraints

- Recognized YouTube URL forms: `https://www.youtube.com/...`, `https://youtube.com/...`, `https://m.youtube.com/...`, `https://youtu.be/...`. `http://` (non-TLS) is NOT recognized.
- Recognized local video extensions (case-insensitive): `.mov`, `.mp4`, `.mkv`, `.webm`, `.avi`, `.m4v`.
- Local video paths are always resolved to an absolute path (via `Cwd::abs_path`) before any `chdir` happens in `run()` — never stored or used as a relative path.
- Local videos are never copied into the project directory — always referenced by their original absolute path.
- Local mode never prompts for a subtitle language and never runs `yt-dlp` — it always falls through to the existing Whisper transcription fallback.
- No support for user-supplied subtitle files (.srt/.vtt) for local videos — out of scope (YAGNI, per spec's Non-goals).
- The generated HTML `<h1>` title is always the fixed string `"Video transcript"` (both modes — no conditional).
- Full spec: `docs/superpowers/specs/2026-08-10-local-video-source-design.md`.

---

### Task 1: `classify_video_source` — input detection

**Files:**
- Modify: `yt-to-webpage.pl` (add `use Cwd;` near the top, add the new sub after `timestamp_to_seconds`)
- Test: `t/classify_video_source.t` (new)

**Interfaces:**
- Produces: `classify_video_source($arg)` → one of:
  - `undef` — `$arg` is undefined, empty, or matches neither a YouTube URL nor an existing file.
  - `{ type => 'invalid_extension', path => $arg }` — `$arg` is an existing file whose extension isn't in the recognized list. `path` is the **original, unmodified** argument (not resolved to absolute) — this hash is only used for an error message, never passed to `ffmpeg`/`whisper`.
  - `{ type => 'youtube', url => $arg }` — `$arg` matched a recognized YouTube URL form. `url` is the original, unmodified argument.
  - `{ type => 'local', path => <absolute path> }` — `$arg` is an existing file with a recognized video extension. `path` is always absolute, via `Cwd::abs_path($arg)`.

- [ ] **Step 1: Write the failing test**

Create `t/classify_video_source.t`:

```perl
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use File::Temp qw(tempdir);
use Cwd qw(abs_path getcwd);

require "$RealBin/../yt-to-webpage.pl";

# --- undef / empty arg ---
is(classify_video_source(undef), undef, "undef arg returns undef");
is(classify_video_source(""), undef, "empty string arg returns undef");

# --- YouTube URL forms ---
for my $url (
    "https://www.youtube.com/watch?v=abc123",
    "https://youtube.com/watch?v=abc123",
    "https://m.youtube.com/watch?v=abc123",
    "https://youtu.be/abc123",
) {
    is_deeply(classify_video_source($url), { type => 'youtube', url => $url },
        "recognizes $url as a youtube source");
}

# http (non-TLS) is intentionally NOT recognized
is(classify_video_source("http://www.youtube.com/watch?v=abc123"), undef,
    "http (non-TLS) youtube link is not recognized");

# --- non-existent path ---
is(classify_video_source("/no/such/file-hopefully-1234.mp4"), undef,
    "non-existent local path returns undef");

# --- existing file, unrecognized extension ---
my $dir = tempdir(CLEANUP => 1);
open(my $txt_fh, ">", "$dir/notes.txt") or die $!;
print $txt_fh "hello";
close $txt_fh;
is_deeply(classify_video_source("$dir/notes.txt"),
    { type => 'invalid_extension', path => "$dir/notes.txt" },
    "existing file with unrecognized extension");

# --- existing file, recognized extension (absolute path given) ---
open(my $mov_fh, ">", "$dir/clip.mov") or die $!;
print $mov_fh "fake video bytes";
close $mov_fh;
is_deeply(classify_video_source("$dir/clip.mov"),
    { type => 'local', path => abs_path("$dir/clip.mov") },
    "existing .mov file with absolute path given");

# --- existing file, recognized extension, uppercase extension ---
open(my $mp4_fh, ">", "$dir/CLIP.MP4") or die $!;
close $mp4_fh;
is_deeply(classify_video_source("$dir/CLIP.MP4"),
    { type => 'local', path => abs_path("$dir/CLIP.MP4") },
    "extension match is case-insensitive");

# --- existing file, relative path given: must resolve to absolute ---
my $orig_cwd = getcwd();
chdir($dir) or die $!;
my $result = classify_video_source("clip.mov");
chdir($orig_cwd) or die $!;
is_deeply($result, { type => 'local', path => abs_path("$dir/clip.mov") },
    "relative path is resolved to absolute before chdir happens elsewhere");

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `prove -l t/classify_video_source.t`
Expected: FAIL — `Undefined subroutine &main::classify_video_source called`

- [ ] **Step 3: Write minimal implementation**

In `yt-to-webpage.pl`, add near the top (with the other `use` lines):

```perl
use Cwd;
```

Add the new sub (e.g. right after `timestamp_to_seconds`):

```perl
sub classify_video_source {
    my ($arg) = @_;
    return undef unless defined $arg && length $arg;
    if ($arg =~ m|^https://(?:(?:www\.|m\.)?youtube\.com|youtu\.be)/|) {
        return { type => 'youtube', url => $arg };
    }
    if (-f $arg) {
        if ($arg =~ /\.(mov|mp4|mkv|webm|avi|m4v)$/i) {
            return { type => 'local', path => Cwd::abs_path($arg) };
        }
        return { type => 'invalid_extension', path => $arg };
    }
    return undef;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `prove -l t/classify_video_source.t`
Expected: PASS, all assertions green.

- [ ] **Step 5: Run the full suite to check nothing else broke**

Run: `prove -l t/`
Expected: PASS (all `.t` files, including the pre-existing ones).

- [ ] **Step 6: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/classify_video_source.t
git commit -m "feat(yt): add classify_video_source for youtube/local/invalid input detection"
```

---

### Task 2: `generate_html` — source as `{ label, link }` hash

**Files:**
- Modify: `yt-to-webpage.pl:153-178` (the `generate_html` sub)
- Test: `t/html_generation.t` (modify existing)

**Interfaces:**
- Consumes: nothing new from Task 1 (independent of `classify_video_source` — only the shape of its own second argument changes).
- Produces: `generate_html($selected, $source_view)` where `$source_view = { label => $text, link => $url_or_undef }`:
  - `link` defined → renders `Source: <a href="$link" target="_blank">$label</a>` and, per moment, `<a href="${link}&t=${seconds}" target="blank" class="videolink">#</a>`.
  - `link` undef → renders `Source: $label` (plain text, `escape_html`'d) and no per-moment `<a class="videolink">` at all.
  - `<h1>` is always the fixed string `"Video transcript"`.
- Task 3 will call this with a hash it builds itself — it does not need anything else from this task beyond the signature above.

- [ ] **Step 1: Update the test to the new expected behavior**

Replace the relevant part of `t/html_generation.t` (keep the `seconds_to_filename`/`escape_html` tests above unchanged) — replace everything from `my @selected = (` to the end with:

```perl
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `prove -l t/html_generation.t`
Expected: FAIL — `generate_html` still takes a bare string, so `$source_view->{label}` / `->{link}` in the sub itself won't exist yet; the youtube-mode assertions on title text (`Video transcript` vs current `Youtube transcript`) and the local-mode assertions will fail.

- [ ] **Step 3: Write minimal implementation**

Replace the `generate_html` sub in `yt-to-webpage.pl` (currently lines 153-178) with:

```perl
sub generate_html {
    my ($selected, $source_view) = @_;
    my $source_html = defined $source_view->{link}
        ? qq{<a href="$source_view->{link}" target="_blank">$source_view->{label}</a>}
        : escape_html($source_view->{label});

    my $html = <<"HEADER";
<html>
<head>
 <link rel="stylesheet" type="text/css" href="styles.css" />
</head>
<body>

<h1>Video transcript</h1>
Source: $source_html

<ul>
HEADER
    foreach my $m (@$selected) {
        my $seconds = $m->{timestamp_seconds};
        my $ts_filename = seconds_to_filename($seconds);
        my $escaped_text = escape_html($m->{text});
        my $videolink = defined $source_view->{link}
            ? qq{<a href="$source_view->{link}&t=${seconds}" target="blank" class="videolink">#</a>}
            : '';
        $html .= qq{<li>
	<div class="grab"><img src="images/$ts_filename.jpg" /></div><div class="subtitle"><span id="$seconds">$escaped_text</span>
$videolink
	</div></li>\n};
    }
    $html .= "\n</ul>\n</body>\n</html>";
    return $html;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `prove -l t/html_generation.t`
Expected: PASS, all assertions green.

- [ ] **Step 5: Run the full suite to check nothing else broke**

Run: `prove -l t/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl yt/Youtube2Webpage/t/html_generation.t
git commit -m "feat(yt): generate_html accepts a {label,link} source view instead of a bare url"
```

---

### Task 3: Wire `classify_video_source` and the new `generate_html` signature into `run()`

**Files:**
- Modify: `yt-to-webpage.pl:273-335` (the `run` sub)

**Interfaces:**
- Consumes: `classify_video_source($arg)` from Task 1 (exact return shapes above); `generate_html($selected, $source_view)` from Task 2 (`$source_view = { label, link }`).
- Produces: nothing new for later tasks — this is the top-level orchestration, not tested in isolation. Verified by running the full test suite plus the existing `make example` regression check.

This task has no isolated unit test — `run()` is the script's top-level orchestration and isn't unit-tested anywhere in `t/` (confirmed: none of the existing `.t` files call `run()`; they test the pure subs and I/O wrappers it calls). Correctness here is verified by (a) the full `prove -l t/` suite still passing — it exercises every sub `run()` calls — and (b) the existing `make example` end-to-end smoke test for the YouTube path, which must keep working unchanged.

- [ ] **Step 1: Replace the argument validation and acquisition logic**

In `yt-to-webpage.pl`, replace the `run` sub (currently lines 273-335) with:

```perl
sub run {
    my $slug = shift @ARGV;
    my $arg = shift @ARGV;

    my $source = classify_video_source($arg);

    if (!$source) {
        print STDERR "Usage:\n";
        print STDERR "$0 project-name \"https://www.youtube.com/watch?v=jNQXAC9IVRw\"\n";
        print STDERR "$0 project-name /path/to/local-video.mp4\n";
        exit 1;
    }

    if ($source->{type} eq 'invalid_extension') {
        print STDERR "$source->{path} exists but doesn't look like a video file ";
        print STDERR "(recognized: .mov, .mp4, .mkv, .webm, .avi, .m4v)\n";
        exit 1;
    }

    mkdir($slug) unless -d $slug;
    chdir($slug);

    my $video_file;
    my $source_view;

    if ($source->{type} eq 'youtube') {
        my $lang = prompt_subtitle_language();
        my @ytdlp_cmd = build_ytdlp_cmd($source->{url}, $lang);
        my $ytdlp_output = run_ytdlp(@ytdlp_cmd);
        ($video_file = $ytdlp_output) =~ s/\s+\z//;
        $source_view = { label => $source->{url}, link => $source->{url} };
    } else {
        $video_file = $source->{path};
        $source_view = { label => basename($source->{path}), link => undef };
    }

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

    my $html = generate_html(\@selected_moments, $source_view);
    open(my $out, '>', 'index.html');
    print $out $html;
    close $out;

    print "Done. Open index.html in $slug/ to view the result.\n";
}
```

Note what changed vs. the current sub: the `!$url || $url !~ ...` check is gone (replaced by `classify_video_source` + the two new early-exit blocks above `mkdir($slug)`); the `youtube`/`local` branch decides `$video_file` and `$source_view` before the shared `has_vtt_files(...)` block, which is otherwise untouched; the final `generate_html(\@selected_moments, $url)` call becomes `generate_html(\@selected_moments, $source_view)`.

- [ ] **Step 2: Add the missing `use File::Basename` import**

`basename()` is now called in `run()`. Add near the other `use` lines at the top of `yt-to-webpage.pl`:

```perl
use File::Basename qw(basename);
```

- [ ] **Step 3: Run the full suite**

Run: `prove -l t/`
Expected: PASS — this confirms every sub `run()` calls still behaves correctly; it does not exercise `run()` itself (no test file calls it), which is expected per this task's Interfaces note above.

- [ ] **Step 4: Manual regression smoke test — YouTube path unchanged**

Run: `make example` (from `yt/Youtube2Webpage/`)
Expected: succeeds exactly as before (downloads "Me at the zoo", generates `example/index.html` with a clickable YouTube source link and per-moment `#` deep links). This confirms the `youtube` branch still works end-to-end after the refactor.

- [ ] **Step 5: Manual smoke test — local video path**

Pick any short local video file you have (a few seconds is enough — this is just confirming the *plumbing* works, not producing a real transcript). From `yt/Youtube2Webpage/`, run:

```bash
./yt-to-webpage.pl local-smoke-test /path/to/any/short/local-video.mp4
```

Expected: no subtitle-language prompt appears; the script goes straight to "No subtitles found for this video. Falling back to local Whisper transcription..."; on success, `local-smoke-test/index.html` shows `<h1>Video transcript</h1>` and `Source: local-video.mp4` as plain text (no link), with no `#` per-moment links. Delete `local-smoke-test/` afterward — it's a throwaway smoke test directory, not a committed artifact.

This is also the point where the user can run the script against their real documentary (`/Volumes/1_ET/EXPORTS/FINAL/TEFQNC_20260807_GV5.mov`) — that run is the original motivation for this feature, but it's a real multi-minute Whisper transcription and Claude call, so it's a separate, longer-running manual step rather than part of this quick smoke test.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/yt-to-webpage.pl
git commit -m "feat(yt): wire local video source into run() — skip yt-dlp/prompt, reuse whisper fallback"
```

---

### Task 4: Documentation — `README.md`

**Files:**
- Modify: `yt/Youtube2Webpage/README.md`

**Interfaces:** None — documentation only, no code interfaces.

`CONTEXT.md` was already updated during spec grilling (2026-08-10) and is not part of this task.

- [ ] **Step 1: Update the opening paragraph**

In `README.md`, replace:

```markdown
Youtube-to-Webpage is a Perl script to create a webpage from a Youtube video with a transcript generated from the video's closed captions (or a local Whisper transcription, if none are available), paired with one screenshot per **key moment** — a topic change or new piece of content, picked by Claude — instead of one screenshot per subtitle line.
```

with:

```markdown
Youtube-to-Webpage is a Perl script to create a webpage from a Youtube video, or a local video file, with a transcript generated from the video's closed captions (or a local Whisper transcription, if none are available — always the case for local video files), paired with one screenshot per **key moment** — a topic change or new piece of content, picked by Claude — instead of one screenshot per subtitle line.
```

- [ ] **Step 2: Update the "Using" section with the local-file invocation form**

Replace:

````markdown
## Using

To use, run the Perl script with a name for the folder to create, and the video URL. For example:

```./yt-to-webpage.pl project-name "https://www.youtube.com/watch?v=jNQXAC9IVRw"```

The script will interactively ask for a **preferred subtitle language** (e.g. `en`, `es`). This only controls which subtitle track yt-dlp downloads when a video has more than one — it does not translate anything; whatever language the transcript is in is the language the generated page will show it in.

If the video has no subtitles at all (neither manual nor auto-generated), the script automatically falls back to transcribing the audio locally with Whisper (`turbo` model, auto-detected language) instead of failing.

Video quality is capped at 720p — plenty for legible screenshots while keeping downloads reasonably fast.
````

with:

````markdown
## Using

To use, run the Perl script with a name for the folder to create, and either a YouTube video URL or the path to a local video file. For example:

```./yt-to-webpage.pl project-name "https://www.youtube.com/watch?v=jNQXAC9IVRw"```
```./yt-to-webpage.pl project-name /path/to/local-video.mp4```

Recognized local video extensions: `.mov`, `.mp4`, `.mkv`, `.webm`, `.avi`, `.m4v`. The local file is read in place — it is never copied into the project directory.

For a YouTube URL, the script will interactively ask for a **preferred subtitle language** (e.g. `en`, `es`). This only controls which subtitle track yt-dlp downloads when a video has more than one — it does not translate anything; whatever language the transcript is in is the language the generated page will show it in. For a local video file, this question is never asked — there is no YouTube subtitle track to choose, so the script always transcribes locally with Whisper instead.

If a YouTube video has no subtitles at all (neither manual nor auto-generated), the script automatically falls back to transcribing the audio locally with Whisper (`turbo` model, auto-detected language) instead of failing — the same fallback local video files always use.

Video quality is capped at 720p for YouTube downloads — plenty for legible screenshots while keeping downloads reasonably fast. Local video files are used at their original resolution.
````

- [ ] **Step 3: Proofread the rendered file**

Run: `cat README.md` and read it top to bottom — confirm the two invocation forms both render as separate code blocks (not merged into one), and that the flow of the "Using" section still reads naturally.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/BIWIN/skills
git add yt/Youtube2Webpage/README.md
git commit -m "docs(yt): document the local video file invocation form"
```
