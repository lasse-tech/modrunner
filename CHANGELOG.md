# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Two colour sets for the classic interface, switchable while the app runs from
  the View menu, from Settings, or from the button in the player's VIEW row:
  **incudex**, ember `#F97D4E` on slate `#1D242F`, the default; and
  **lasse-web**, cyan `#2EE6FF` and magenta `#FF3DBD` on near-black `#12141F`.
  Both come from the design tokens of the sibling projects of the same name
- `Sources/ModRunnerKit/Palette.swift`, the one place the interface colours are
  written down, as bytes and with no toolkit types in it, so the app, the pixel
  renderer and a test with no window server can all read it
- A one-off migration of the stored defaults: `skin` = `"amiga"` becomes
  `"classic"`, and `windowExtraHeight.amiga` / `windowOrigin.amiga` are carried
  over to their `.classic` keys, so an existing installation keeps its skin and
  its window where they were
- `docs/redesign/mockup.html`, an HTML mockup of the redesign in both colour
  sets
- The engine and `modrunner` build and pass their tests on Linux and Windows,
  checked on every push. The interface stays macOS only
- Audio output is behind a backend protocol: AVFoundation on Apple's platforms,
  miniaudio everywhere else, selectable with `MODRUNNER_AUDIO_BACKEND`
- `ModRunnerSkin`: the classic interface drawn into a pixel buffer with no
  toolkit under it — palette, bevels, an 8×8 bitmap face drawn for the project,
  meters, sliders, buttons, the tracker panel and the playlist
- `modrunner screenshot` renders that interface to a PNG without a window, which
  is how it is checked on machines that cannot yet show it
- Note notation moved into the engine; the tracker view, `dump` and the skin had
  a copy each

### Changed

- The second interface is now **Classic**, an original design, and no longer a
  re-creation of the AmigaOS 3.x Workbench. The shapes it is built from stay —
  bevelled panels, two-pixel edges, recessed readouts, a monospaced grid — but
  the colours, the window gadgets and the typeface are the project's own.
  `Skin.amiga` is `Skin.classic`, shown as "Classic" / "Klassisch" under the
  key `skin.classic`
- The grey Workbench palette is gone, and both of the colour sets that replace
  it are dark, which inverts the bevel: the shine is the lightest frame tone
  (`#3A4757`, `#2B3040`) instead of white, and the shadow is the deepest ground.
  The rule — light above and to the left — is unchanged, and is what keeps the
  surfaces legible
- The window gadgets are redrawn in a shape language of their own, one bar motif
  carried through all five: close collapses a bar in three steps, 5:3:1;
  iconify lays everything down on the baseline; zoom grows a row 1:2:3, the same
  progression as the Fibonacci VU mark; depth is two offset plates; sizing is a
  corner being pulled. Their positions and their functions are where the hand
  expects them
- The palette is one source for both surfaces — the SwiftUI app and the portable
  pixel renderer read the same `Palette` in `ModRunnerKit`. It used to be
  written out four times, and the copies had drifted
- The app no longer bundles a typeface or looks for an installed Topaz. The
  classic interface draws from the project's own 8×8 bitmap face, and the native
  one asks for JetBrains Mono, IBM Plex Mono, Menlo, Monaco, in that order
- The trademark notice in `README.md`, `NOTICE` and `THIRD-PARTY-NOTICES.md` no
  longer describes the interface as a re-creation in the Workbench idiom, and
  says instead why Amiga is named at all: the file formats and the output
  filter. `AmigaFilter`, the `menu.amigaFilter` string and the `amigaFilter`
  default are unchanged — they name an audio behaviour, not a skin

### Removed

- `AmigaTheme.swift`, `AmigaControls.swift`, `AmigaSkinView.swift` and
  `ModRunnerSkin/Workbench.swift`, replaced by `ClassicTheme.swift`,
  `ClassicControls.swift`, `ClassicSkinView.swift`, `SkinMetrics.swift` and
  `ModRunnerSkin/Theme.swift`

## [1.0.0] - 2026-08-12

### Added

- MMD0 and MMD1 loader, following the pointer discipline the format
  specification insists on, with bounds checks on every structure
- Paula-style replayer: four or more voices, Amiga period table, per-voice
  looping, Catmull-Rom resampling, soft clipping
- Effects `0x00`–`0x0F`, including the `0x0F` misc group and the `$80`–`$C0`
  range of `0x0C` that rewrites an instrument's default volume
- Extended MMD1 effects `0x11`–`0x1F`: single-tick pitch and volume slides,
  ProTracker-style vibrato, set finetune, line loop, cut note, sample start
  offset, jump to next sequence entry, replay line, note delay and retrigger
- AmigaOS 3.x style interface: bevelled panels, per-voice VU meters, transport,
  song position scrubbing, playlist with drag and drop
- Tracker view showing the current block's note data under a fixed playhead,
  toggleable and remembered between launches; the window resizes to match
- Module statistics in the status line: blocks, lines, notes, samples
- Switchable visualisation: per-voice levels or an oscilloscope of the output
- Display synchronised to the speakers, compensating for output latency
- The window position is remembered, separately per skin, and discarded when it
  would land on a screen that is no longer attached
- ProTracker `.mod` support, loaded into the same model and played by the same
  replayer; the effect dialect is carried on the module, since the command
  numbers mean different things in the two formats
- The Amiga output filter, switchable and remembered between launches
- Per-channel mute and solo
- Opens modules from the command line and from the Finder; `.med` and `.mod`
  are declared as document types with their own UTIs, and `make associate`
  registers ModRunner as their default application
- Offline-rendering test suite and a WAV export for listening checks
- Four example modules by the author

### Notes

- MMD2 and MMD3 are detected and reported rather than played
- Synthetic, hybrid and MIDI instruments are parsed but stay silent; hold/decay
  (`0x08`) and synth jump (`0x0E`) are not implemented
- Playback verified against libxmp: 0.985 envelope correlation at zero lag,
  duration within 0.4 s over a 3:27 module
