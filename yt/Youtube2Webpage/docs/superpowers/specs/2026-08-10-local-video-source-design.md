# Local Video Source — Design

**Date:** 2026-08-10
**Status:** Approved

## Problem

`yt-to-webpage.pl` only accepts a YouTube URL as its video source: it validates
the second CLI argument against `^https://www\.youtube\.com`, downloads the
video and subtitles with `yt-dlp`, and links back to that URL in the generated
HTML (both the "Source:" line and the per-moment `#` jump link).

The user wants to run the same pipeline (transcript + Claude-selected key
moments + screenshots + HTML page) against a video file that lives on local
disk and was never uploaded to YouTube — e.g. a personal documentary export.

## Goals

- Accept a local video file path as an alternative to a YouTube URL, as a
  permanent second input mode of the script (not a one-off script hack).
- Reuse all existing pipeline logic (VTT parsing, Claude prompt, moment
  matching, screenshot capture) unchanged — only the video/subtitle
  *acquisition* step and the HTML *source rendering* differ by mode.
- Keep the change YAGNI-scoped: no support (yet) for user-supplied subtitle
  files for local videos, no copying of the local video into the project
  directory.

## Non-goals

- Supporting a pre-existing subtitle file (.srt/.vtt) for a local video. The
  user confirmed they never have one for their local videos; always fall
  back to Whisper transcription in local mode. Defer until actually needed.
- Copying the local video file into the project directory. The source file
  can be several GB and lives on another volume; referencing its absolute
  path is enough for both `whisper` and `ffmpeg`.
- Any change to non-YouTube URL schemes (e.g. Vimeo). Out of scope.

## Design

### 1. Input source detection

New pure, testable function:

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

The `invalid_extension` case (file exists, but its extension isn't a
recognized video format) is distinguished from the generic `undef` case
(argument matches neither a YouTube URL nor an existing file) so `run()`
can give a specific, helpful error — "this exists but doesn't look like a
video file" is a different mistake than "this isn't a URL or a path at
all", and conflating them into one generic usage message would leave the
user guessing which one they hit.

Widens YouTube-URL recognition beyond the current exact
`^https://www\.youtube\.com` match: `youtube.com` with or without `www.`,
`m.youtube.com`, and the `youtu.be` short-link domain. This was a
pre-existing gap unrelated to local-video support, but since this function
replaces the only place that check lives, it's fixed in the same change
rather than left inconsistent. `http://` (non-TLS) links are intentionally
still not recognized — not worth the YAGNI cost for links this old.

Replaces the current inline check in `run()`, at the same point in
`run()` — i.e. **before** `mkdir($slug)`/`chdir($slug)`. This matters: the
CLI argument may be a relative path (`./doc.mov`), which only resolves
correctly relative to the original working directory. `classify_video_source`
resolves it to an absolute path with `Cwd::abs_path` immediately, so the
`local` hash always carries an absolute path — safe to use after the
subsequent `chdir` into the project directory regardless of how the user
wrote it on the CLI.

`run()` calls this once:
- `undef` → existing two-line usage message (now showing both forms),
  `exit 1`.
- `{ type => 'invalid_extension', ... }` → specific message, e.g. `"$arg
  exists but doesn't look like a video file (recognized: .mov, .mp4,
  .mkv, .webm, .avi, .m4v)\n"`, `exit 1`.
- `{ type => 'youtube' | 'local', ... }` → proceeds as below.

Usage message (both lines shown together on any `undef` failure):

```
Usage:
  yt-to-webpage.pl project-name "https://www.youtube.com/watch?v=jNQXAC9IVRw"
  yt-to-webpage.pl project-name /path/to/local-video.mp4
```

### 2. Video/subtitle acquisition (in `run()`)

Branch on `$source->{type}` right after `mkdir($slug)`/`chdir($slug)`:

- **`youtube`** (unchanged): `prompt_subtitle_language()` →
  `build_ytdlp_cmd` → `run_ytdlp` → existing `has_vtt_files` check → Whisper
  fallback if no subs.
- **`local`**: skip the subtitle-language prompt and the entire `yt-dlp`
  step. `$video_file` = `$source->{path}` (absolute, not copied). Because
  the freshly-created project directory never contains a `.vtt` file in
  this mode, the existing `unless (has_vtt_files('.'))` check naturally
  triggers the Whisper fallback — no change needed to that logic, only to
  what runs *before* it.

`build_whisper_cmd` and `build_ffmpeg_cmd` already take a video file path
as a plain argument and are unaffected by where that path points.

### 3. HTML generation

`generate_html($selected, $source_view)` changes its second parameter from a
bare URL string to a hash:

```perl
{ label => $text, link => $url_or_undef }
```

- **`youtube`**: `{ label => $url, link => $url }` — identical rendering to
  today (clickable "Source:" line, per-moment `#` link with `&t=<seconds>`).
- **`local`**: `{ label => basename($path), link => undef }` — renders:
  - `Source: TEFQNC_20260807_GV5.mov` as plain text (no `<a>`).
  - No per-moment `<a class="videolink">#</a>` at all (nothing to jump to).
- The `<h1>` title becomes the fixed string `"Video transcript"` in both
  modes (dropping the YouTube-specific wording; no conditional needed).

`run()` builds this hash right before calling `generate_html`, based on
`$source->{type}`.

### 4. Testing

- New `t/classify_video_source.t` (Test::More, no real external tools):
  YouTube URL in each recognized form (`www.youtube.com`, bare
  `youtube.com`, `m.youtube.com`, `youtu.be`) → `youtube` hash with
  absolute-path-irrelevant `url`; existing local video file (temp fixture,
  recognized extension) → `local` hash with an absolute `path` (assert via
  `Cwd::abs_path` on the fixture, not a hardcoded string, so the test isn't
  tied to the tmpdir layout); existing local file with an unrecognized
  extension (e.g. `.txt` fixture) → `invalid_extension` hash; non-existent
  path → `undef`; empty/undef arg → `undef`.
- Update `t/html_generation.t` for the new `$source_view` hash shape: one
  case with `link` defined (existing YouTube behavior), one with
  `link => undef` (local — asserts plain text source and absence of the
  per-moment link).
- No changes needed to whisper/ffmpeg command-building tests — those subs
  are untouched.

### 5. Documentation

- `README.md` opening paragraph: reword "...create a webpage from a Youtube
  video..." to acknowledge the local-file mode too, without renaming the
  project/repo (out of scope — bigger change touching `example/`, links,
  script name).
- `README.md` "Using" section: add the local-file invocation form next to
  the YouTube URL form, and a line noting local videos always use the
  Whisper fallback (no subtitle-file support yet).
- `CONTEXT.md`: **done** (during spec grilling, 2026-08-10) — added
  **Fuente de vídeo** and **Vídeo local** terms, linked into
  `## Relationships`, and narrowed **Idioma de subtítulos preferido** to
  note it only applies when the source is a YouTube URL.

## Open questions

None — all resolved during brainstorming (2026-08-10) and spec grilling
(2026-08-10): absolute-path normalization before `chdir`, widened YouTube
URL recognition, extension validation with a distinct `invalid_extension`
outcome, the two-line usage message, and the README/CONTEXT.md wording
gaps this created.
