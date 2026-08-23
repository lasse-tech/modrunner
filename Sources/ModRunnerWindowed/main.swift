import ModRunnerCommands

// The windowed build, linked with /SUBSYSTEM:WINDOWS so it opens without a
// console behind it. With no arguments it opens the player rather than printing
// usage, because there is nowhere for that to be printed — and for the same
// reason nothing else is printed either: what would have gone to stderr goes to
// a requester, so a module that fails to load says so instead of leaving the
// double-click looking like nothing happened.
CLI.main(defaultCommand: "window", hasConsole: false)
