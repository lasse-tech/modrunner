# Prompt for the headless session

Paste the block below as the first message of a new Claude Code session, with
`/Users/lars/git/modrunner` as the working directory.

---

Implementiere den Headless-Betrieb für ModRunner. Der Player ist eine macOS-App
(SwiftUI + AVAudioEngine) für MED/OctaMED-Module; Loader und Replayer sind
bereits frei von UI-Abhängigkeiten und importieren nur Foundation. Lies zuerst
`README.md`, `CONTRIBUTING.md` und `docs/HEADLESS-PROMPT.md`.

**Ziel:** ModRunner soll ohne GUI nutzbar sein — skriptbar, in CI, per Cron.

**1. Target-Split.** Aktuell liegt alles in einem Executable-Target, dessen
`@main` unbedingt `NSApplication.shared.run()` aufruft. Das ist der einzige
Blocker. Teile auf:

```
Sources/ModRunnerKit/   MMDModule, MMDLoader, Replayer, PlaybackHistory,
                        WAVWriter, AudioOutput          (Bibliothek)
Sources/ModRunner/      GUI, hängt von Kit ab
Sources/modrunner/      CLI, hängt von Kit ab
```

Das kostet `public`-Annotationen auf der API-Oberfläche von Kit. `WAVWriter`
liegt derzeit im Test-Target (`Tests/ModRunnerTests/ReplayerTests.swift`) und
muss in den Kit umziehen. Die Tests importieren danach die Bibliothek statt des
Executables.

**2. CLI**, Argumentparsing von Hand — **keine neue Abhängigkeit**, das Projekt
hat bewusst null Fremdabhängigkeiten (siehe `THIRD-PARTY-NOTICES.md`):

```
modrunner info   <modul>...                  Format, Blöcke, Spuren, Zeilen,
                                             Noten, Instrumente, Dauer
modrunner render <modul> -o out.wav [--seconds N] [--rate 44100]
                                             -o - schreibt nach stdout
modrunner dump   <modul> [--block N]         Patterndaten als Text
modrunner play   <modul>...                  live, braucht ein Audiogerät
```

Exitcode ≠ 0 bei Ladefehlern, damit sich das Ding als Batch-Validator für
Modulsammlungen eignet.

**3. `play` headless ist nicht zuverlässig** — `AVAudioEngine` braucht ein
Ausgabegerät, und über SSH ohne angemeldete Aqua-Session hat CoreAudio meist
keines. Lass es mit einer klaren Fehlermeldung scheitern, statt es zu
verschweigen. `info`, `render` und `dump` müssen überall laufen.

**4. Makefile** um passende Targets ergänzen und `README.md` nachziehen.

**Verifikation** — bitte nicht auf „kompiliert" verlassen:

- `make check` muss grün bleiben (aktuell 17 Tests, 7 übersprungen)
- `modrunner render` gegen `libxmp` gegenprüfen; die Baseline steht in
  `CONTRIBUTING.md`: Hüllkurven-Korrelation **0,985 bei Lag 0**, Dauer 207,0 s
  gegen 207,4 s Referenz für `Examples/Happy Hour.med`. Ein Abfall braucht eine
  Erklärung.
- `modrunner info` gegen `xmp --load-only` gegenprüfen (Blöcke, Sequenzlänge,
  Instrumente, Dauer)
- Ein Test, der die CLI über alle vier Beispielmodule laufen lässt

**Kontext, der Zeit spart:**

- Die Formatspec liegt in `docs/`. Die Effektbefehle stehen dort **nicht** —
  die sind in Anhang A/B des OctaMED-SoundStudio-Handbuchs, das aus
  Lizenzgründen nicht im Repo liegt (`NOT PUBLIC DOMAIN`).
- `Replayer.render()` funktioniert bereits vollständig offline; die Testsuite
  rendert damit ohne Audiogerät. Es fehlt nur der Einstiegspunkt.
- `Replayer.setOutputLatency()` verschiebt die Anzeige gegen die Ausgabe. Für
  Offline-Rendering muss die Latenz **0** bleiben.
- Lizenz ist Apache-2.0; neue Dateien brauchen keinen Header, aber neue
  Fremdbestandteile gehören in `THIRD-PARTY-NOTICES.md`.
- Das Repo ist privat: `github.com/lasse-tech/modrunner`, Branch `main`.
