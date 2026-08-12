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

You need macOS 13 or newer and a Swift 6 toolchain. There are no third-party
dependencies and none should be added without a good reason.

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

## Licensing of contributions

Contributions are accepted under the Apache License 2.0, the same licence the
project uses. If you add third-party material, record it in
`THIRD-PARTY-NOTICES.md` with its licence — and make sure it actually carries a
licence that permits redistribution. Attribution alone is not enough.
