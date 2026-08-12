# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
