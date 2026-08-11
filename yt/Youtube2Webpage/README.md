# Youtube-to-Webpage

Youtube-to-Webpage is a Perl script to create a webpage from a Youtube video, or a local video file, with a transcript generated from the video's closed captions (or a local Whisper transcription, if none are available — always the case for local video files), paired with one screenshot per **key moment** — a topic change or new piece of content, picked by Claude — instead of one screenshot per subtitle line.

```./yt-to-webpage.pl project-name "videoURL"```

## Dependencies

The project is built upon:

* [yt-dlp](https://github.com/yt-dlp/yt-dlp) — video + subtitle download
* [ffmpeg](https://ffmpeg.org/) — screenshot capture
* [whisper](https://github.com/openai/whisper) (`turbo` model) — local transcription fallback when a video has no captions at all
* [claude](https://claude.com/claude-code) CLI — picks the key moments from the transcript (`claude -p`, must be logged in)
* A Chrome browser installed and logged into YouTube — yt-dlp uses `--cookies-from-browser chrome` to avoid rate-limiting

## Using

To use, run the Perl script with a name for the folder to create, and either a YouTube video URL or the path to a local video file. For example:

```./yt-to-webpage.pl project-name "https://www.youtube.com/watch?v=jNQXAC9IVRw"```
```./yt-to-webpage.pl project-name /path/to/local-video.mp4```

Recognized local video extensions: `.mov`, `.mp4`, `.mkv`, `.webm`, `.avi`, `.m4v`. The local file is read in place — it is never copied into the project directory.

For a YouTube URL, the script will interactively ask for a **preferred subtitle language** (e.g. `en`, `es`). This only controls which subtitle track yt-dlp downloads when a video has more than one — it does not translate anything; whatever language the transcript is in is the language the generated page will show it in. For a local video file, this question is never asked — there is no YouTube subtitle track to choose, so the script always transcribes locally with Whisper instead.

If a YouTube video has no subtitles at all (neither manual nor auto-generated), the script automatically falls back to transcribing the audio locally with Whisper (`turbo` model, auto-detected language) instead of failing — the same fallback local video files always use.

Video quality is capped at 720p for YouTube downloads — plenty for legible screenshots while keeping downloads reasonably fast. Local video files are used at their original resolution.

## Testing

The pure logic (VTT parsing, Claude prompt/response handling, moment matching,
HTML generation, and the error-checking around each external tool call) has
a `Test::More` suite in `t/`. Run it with:

```prove -l t/```

This does not call any real external tool (yt-dlp/whisper/ffmpeg/claude) — it
uses fixtures and fake executables. To validate the full pipeline end-to-end,
run the script itself against a short video, e.g. the one in the `Makefile`:

```make example```

## Output

Running the script create a repository according to the following structure:

```
project-name
├── images
│   └── (…).jpg
├── video.vtt
├── video.webm
├── index.html
└── styles.css
```

* The index.html file is the generated webpage.
* The images directory contains one screenshot per key moment, named according to their timeframe ```hours-minutes-seconds.jpg```.
* The vtt file contains the captions (from yt-dlp, or from the Whisper fallback).
* The webm file contains the video.
* The css file styles the webpage.

## Example

You can see an example at https://obra.github.io/Youtube2Webpage/example/
