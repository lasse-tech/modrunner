# ModRunner

![Unreleased](https://img.shields.io/badge/status-unreleased-EDE6E0?labelColor=231D18)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-17130F?logo=apple&logoColor=white)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-FF6B35?logo=swift&logoColor=white)
![No dependencies](https://img.shields.io/badge/dependencies-none-2E7D32)
![Licence Apache-2.0](https://img.shields.io/badge/licence-Apache--2.0-3B67A2)
![Formats](https://img.shields.io/badge/formats-MMD0%20%C2%B7%20MMD1%20%C2%B7%20MOD-FFA997?labelColor=17130F)
![Languages](https://img.shields.io/badge/languages-EN%20%C2%B7%20DE-3B67A2?labelColor=17130F)

A small macOS player for Amiga tracker modules — MED, OctaMED and ProTracker —
from the late eighties and early nineties, presented in the style of the
AmigaOS 3.x Workbench interface.

<!-- Screenshot: run the app and grab the window if you want one in the README. -->

## What it does

- Reads **MMD0** and **MMD1** MED/OctaMED modules (MMD2/MMD3 are detected and
  reported, not played) and **ProTracker `.mod`** files (`M.K.`, `M!K!`, `FLT4`,
  `xxCH` and friends, 2 to 32 channels)
- Paula-style replayer: per-voice period, volume and looping, Catmull-Rom resampling
- Effects `0x00`–`0x0F`: arpeggio, pitch slides, portamento, vibrato, tremolo,
  volume slides, TPL slider, position jump, set volume (including the `$80`–`$C0`
  range that rewrites an instrument's default volume), and the `0x0F` misc group
  (tempo, pattern break, note delay by half/third/two-thirds of a line,
  retrigger, set-pitch-without-replay, note off, end of song)
- Extended MMD1 effects `0x11`–`0x1F`: single-tick pitch and volume slides,
  ProTracker-style vibrato, set finetune, line loop, cut note, sample start
  offset, jump to next sequence entry, replay line, note delay and retrigger
- Playlist with drag & drop; drop a single module or a whole drawer
- **Two interfaces**, switchable at any time from the View menu (⌘1 / ⌘2) or the
  buttons in the window itself. They share the model and the replayer, so
  switching mid-song changes nothing you hear:
  - **Native** — system materials and typography, SF Symbols, the ModRunner
    palette, a continuously scrolling tracker and animated level meters
  - **Workbench** — the AmigaOS 3.x re-creation, chunky and discrete on purpose
- Tracker view: the note data of the current block moving under a fixed
  playhead, in OctaMED's notation, with beat lines marked — toggle it with the
  **Tracks** button or ⌘T, and the window resizes to match
- **Full-screen player** (⌃⌘F, or the green window gadget) — the pattern as big
  as the display allows, scrolling under a fixed playhead, with the information
  strips fading away while the mouse is still. Esc leaves, space plays, ←/→ move
  by position.
- **Mini player** (⌃⌘M) — a floating strip that stays above other windows while
  you work
- Both follow whichever interface is selected, in the same two styles
- **Recently played**, in the File menu — recorded when a module is actually
  played, not when a folder of them is loaded
- **English and German**, following the system language unless told otherwise in
  Settings (⌘,)
- Per-voice level meters with mute and solo, song position scrubbing,
  transport, volume
- The Amiga output filter, switchable (⌘F). An A500 put a fixed RC stage and a
  switchable two-pole Butterworth between Paula and the sockets, and a lot of
  period music was written through them. Off by default, so playback stays
  comparable with other players.
- Opens modules passed on the command line or double-clicked in the Finder

Synthetic and hybrid instruments are parsed but stay silent — they need OctaMED's
waveform sequencer, which is not implemented. MIDI instruments are silent too.

## Build and run

```sh
make build      # compile
make test       # loader + replayer tests
make app        # build/ModRunner.app
make run        # build and play the bundled examples
make install    # copy the app into /Applications
make associate  # open .med and .mod files with ModRunner
make help       # every target, with the variables you can override
```

Requires macOS 13+ and a Swift 6 toolchain. There are **no third-party
dependencies** — only Apple's own SwiftUI, AppKit and AVFoundation.

You can also point the app at your own modules:

```sh
open build/ModRunner.app --args ~/path/to/modules
```

Modules can be dropped onto the window, opened from the Finder, or passed on the
command line — individually or as a whole folder.

## Examples

`Examples/` holds four MED modules from 1993 by the author of this repository,
originally released as the *Magic Noises* collection. They are what the test
suite renders and what `make run` plays. See `Examples/README.md` — they are not
covered by the source licence.

## Accuracy

Playback was checked against [libxmp](https://xmp.sourceforge.net/) rendering the
same module:

| Measure | Result |
|---|---|
| Song duration | 207.0 s vs. 207.4 s reference |
| Envelope correlation (20 ms windows) | **0.985**, best lag 0 ms |
| Spectral centroid | tracks the reference within a few percent |
| Mean spectral cosine similarity | 0.79 |

A ProTracker module was checked the same way: 255.0 s against 255.18 s,
**0.964** envelope correlation at zero lag, and 0.93 mean spectral similarity.

The residual spectral difference is the resampling kernel and the mixer's stereo
separation, not note timing or pitch.

To export a render for listening:

```sh
make export MODULE="Examples/Take it slow.med" SECONDS=60 WAV=build/out.wav
```

## Format documentation

`docs/` carries Teijo Kinnunen's specification, which is the authoritative source
for the format:

- `MMD_FileFormat.txt` — Revision 6 (01.02.1996), covers MMD0/MMD1/MMD2/MMD3
- `MED-Format-rev1.txt` — Revision 1 (25.04.1992), MMD0/MMD1 only, and explicitly
  placed in the public domain by its author

The specification does **not** document the effect command set. That lives in
Appendix A and B of the *OctaMED SoundStudio V1.03c Manual* (© RBF Software
1997), which is the authoritative source for effect semantics and is what the
effect handling here was built and corrected against.

That manual is marked **"NOT PUBLIC DOMAIN"** and is therefore deliberately not
included in this repository.

The tempo conversion was cross-checked against OpenMPT's `soundlib/Load_med.cpp`
(BSD-3-Clause, not vendored here — see
<https://github.com/OpenMPT/openmpt/blob/master/soundlib/Load_med.cpp>).

Not implemented: hold/decay (`0x08`) and synth jump (`0x0E`), both of which need
OctaMED's instrument envelope and waveform sequencer.

## Credits

- **Teijo Kinnunen** — MED, OctaMED, and the format specification everything here
  is built on
- **Ed Wiles / RBF Software** — the OctaMED SoundStudio manual, whose appendices
  are the only authoritative record of the player command set
- **The OpenMPT developers** — their MED loader, used to cross-check the tempo
  conversion
- **Claudio Matsuoka and Hipolito Carraro Jr** — libxmp, the reference renderer
  playback accuracy was measured against

Full attribution, licences and the reasoning behind what is and is not included
here: [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## Licence

© 2026 incūdex, Lars Gossard.

Source code is licensed under the [Apache License 2.0](LICENSE). See
[`NOTICE`](NOTICE).

The example modules in `Examples/` are **not** covered by that licence — they are
the author's own music under their own terms, described in
[`Examples/README.md`](Examples/README.md).

## Trademarks

Amiga, AmigaOS and Workbench are trademarks of their respective owners. MED and
OctaMED are the work of Teijo Kinnunen / RBF Software. This project is an
independent reimplementation and is not affiliated with, endorsed by, or derived
from any of them. The interface is an original re-creation in the visual idiom of
the Workbench; no Amiga artwork, icons, fonts or ROM code are included.
