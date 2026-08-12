# Contributing

Thanks for taking an interest. This is a small project with a narrow scope: play
MED and OctaMED modules on macOS, accurately, in a Workbench-flavoured window.

## Getting set up

```sh
make build      # compile
make test       # run the test suite
make app        # build ModRunner.app
make run        # build and play the example modules
make help       # everything else
```

You need macOS 13 or newer and a Swift 6 toolchain. Exactly one piece of
third-party code is in the tree — miniaudio, vendored, and only because Linux
and Windows have no AVFoundation to play through. Nothing is fetched at build
time, and nothing else should be added without a good reason.

## Ground rules for playback changes

The replayer is the part where correctness is hard to eyeball, so it carries the
most process:

1. **Cite the source.** Effect semantics come from Appendix A and B of the
   OctaMED SoundStudio manual; structure and offsets come from Kinnunen's format
   specification in `docs/`. If you change behaviour, say in the commit message
   which document says so. "It sounds better" is not a reason on its own.
2. **Check against a reference.** `xmp` (`brew install xmp`) renders the same
   module independently. Export both and compare — envelope correlation over
   short windows catches timing regressions that the ear will miss:

   ```sh
   make cli
   .build/debug/modrunner render "Examples/Happy Hour.med" -o build/mine.wav
   xmp -q -d wav -o build/ref.wav "Examples/Happy Hour.med"
   ```

   The baseline is in `README.md`: 0.991, 0.977, 0.994 and 0.909 envelope
   correlation for the four bundled modules, every one at zero lag and within
   20 ms of the reference duration. A change that drops any of them needs an
   explanation.
3. **Add a test.** `Tests/ModRunnerTests` renders offline, so playback can be
   asserted without an audio device.

## Diagnostics

Window and audio behaviour is awkward to judge by eye, so the app can report
what it is actually doing. Set these when running the binary directly:

| Variable | What it does |
|---|---|
| `MODRUNNER_PRINT_WINDOW_ID=1` | Prints the window id and frame, then every two seconds the chrome state: skin, style mask, whether a system title bar is layered over the content, origin, button visibility |
| `MODRUNNER_AUDIO_DEBUG=1` | Prints sample rate, device presentation latency, buffer latency and the total the display compensates for; also logs configuration changes |
| `MODRUNNER_AUDIO_BACKEND=miniaudio` | Plays through miniaudio instead of AVFoundation. The macOS default is AVFoundation; this is how the backend Linux and Windows depend on can be exercised on a Mac |
| `MODRUNNER_SIMULATE_DEVICE_CHANGE=1` | Posts a synthetic engine configuration change three seconds after start, to exercise the device-switch path without taking over the machine's audio output |

```sh
MODRUNNER_AUDIO_DEBUG=1 ./build/ModRunner.app/Contents/MacOS/ModRunner "Examples/Happy Hour.med"
```

Views render offscreen rather than being screenshotted, which keeps verification
out of the way of whatever else is on screen:

```sh
MED_SNAPSHOT=/tmp/shots swift test --filter SnapshotTests
```

## Style

Match what is already there: descriptive names, comments that explain *why* and
cite the spec where a magic number comes from, no comment restating the code.
`make fmt` runs swift-format if you have it.

`make lint` runs SwiftLint (`brew install swiftlint`), and CI does the same on
every push. The rules in `.swiftlint.yml` are tuned for a playroutine: short DSP
variable names, hand-aligned period tables and long effect switches are all
fine. `make lint-fix` applies the corrections SwiftLint can make on its own.

## Releasing

Releases are built on a machine that holds the Developer ID certificate, not in
CI. Once per machine, store the notary credentials — your Apple ID, the team id
and an app-specific password from appleid.apple.com, *not* the Apple ID
password:

```sh
make notary-setup
```

Then, with the changelog's `## [Unreleased]` section renamed to the version
being released and everything committed:

```sh
make release VERSION=1.0.0
```

That builds `ModRunner.app` signed with the Developer ID certificate and the
hardened runtime, packs it into `build/ModRunner-1.0.0.dmg` next to an
`/Applications` alias, signs the image, sends it to Apple's notary service,
staples the ticket, tags `v1.0.0` and creates a **draft** GitHub release whose
notes are the changelog section for that version. Look at the draft, then
publish it from the release page. `DRAFT=0` skips the draft step.

The steps are available on their own — `make signed-app`, `make dmg` — and
`make dmg` with `NOTARY_PROFILE=` set to nothing builds and signs the image
without involving Apple, which is the quick way to check a packaging change.
`make app` still produces the ad-hoc signed bundle for everyday development.

## Licensing of contributions

Contributions are accepted under the Apache License 2.0, the same licence the
project uses. If you add third-party material, record it in
`THIRD-PARTY-NOTICES.md` with its licence — and make sure it actually carries a
licence that permits redistribution. Attribution alone is not enough.
