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
    if ($arg =~ m|^https://www\.youtube\.com|) {
        return { type => 'youtube', url => $arg };
    }
    if (-f $arg) {
        return { type => 'local', path => $arg };
    }
    return undef;
}
```

Replaces the current inline regex check in `run()`. `run()` calls this once,
and exits with the existing two-line usage message (now showing both forms)
when it returns `undef`.

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
  YouTube URL → `youtube` hash; existing local file (temp fixture) →
  `local` hash; non-existent path → `undef`; empty/undef arg → `undef`.
- Update `t/html_generation.t` for the new `$source_view` hash shape: one
  case with `link` defined (existing YouTube behavior), one with
  `link => undef` (local — asserts plain text source and absence of the
  per-moment link).
- No changes needed to whisper/ffmpeg command-building tests — those subs
  are untouched.

### 5. Documentation

- `README.md` "Using" section: add the local-file invocation form next to
  the YouTube URL form, and a line noting local videos always use the
  Whisper fallback (no subtitle-file support yet).
- `CONTEXT.md`: add **Vídeo local** as a second recognized source type,
  alongside the existing YouTube-URL-based flow, noting it renders without
  a playback link (filename only).

## Open questions

None — all resolved during brainstorming (2026-08-10).
