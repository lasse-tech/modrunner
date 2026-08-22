import ModRunnerCommands

// The windowed build, linked with /SUBSYSTEM:WINDOWS so it opens without a
// console behind it. With no arguments it opens the player rather than printing
// usage, because there is nowhere for that to be printed.
CLI.main(defaultCommand: "window")
