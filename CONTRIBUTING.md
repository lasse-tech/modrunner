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
   make export MODULE="Examples/Happy Hour.med" SECONDS=207 WAV=build/mine.wav
   xmp -d wav -o build/ref.wav "Examples/Happy Hour.med"
   ```

   The current baseline is an envelope correlation of 0.985 at zero lag. A change
   that drops it needs an explanation.
3. **Add a test.** `Tests/ModRunnerTests` renders offline, so playback can be
   asserted without an audio device.

## Style

Match what is already there: descriptive names, comments that explain *why* and
cite the spec where a magic number comes from, no comment restating the code.
`make fmt` runs swift-format if you have it.

## Licensing of contributions

Contributions are accepted under the Apache License 2.0, the same licence the
project uses. If you add third-party material, record it in
`THIRD-PARTY-NOTICES.md` with its licence — and make sure it actually carries a
licence that permits redistribution. Attribution alone is not enough.
