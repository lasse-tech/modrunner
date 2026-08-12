#!/usr/bin/env swift
//
// Makes ModRunner the default application for MED and ProTracker modules.
//
//   swift Scripts/associate.swift            registers
//   swift Scripts/associate.swift --status   reports without changing anything
//
// The app has to exist somewhere stable first — Launch Services remembers the
// path, so associating a copy in a build directory breaks as soon as it is
// cleaned. `make install` puts it in /Applications; run this afterwards.

import Foundation
import CoreServices

let bundleIdentifier = "de.incudex.modrunner"
let contentTypes = ["de.incudex.modrunner.med", "de.incudex.modrunner.mod"]

func currentHandler(for type: String) -> String {
    (LSCopyDefaultRoleHandlerForContentType(type as CFString, .viewer)?
        .takeRetainedValue() as String?) ?? "(none)"
}

let statusOnly = CommandLine.arguments.contains("--status")

// Launch Services only knows about the declared types once it has seen the
// bundle, so make sure the app is actually installed before claiming anything.
let installed = FileManager.default.fileExists(atPath: "/Applications/ModRunner.app")
if !installed, !statusOnly {
    FileHandle.standardError.write(Data("""
    ModRunner.app is not in /Applications.

    Launch Services stores the path of the handler, so associating a build
    directory would break on the next clean. Run `make install` first.

    """.utf8))
    exit(1)
}

for type in contentTypes {
    if statusOnly {
        print("\(type): \(currentHandler(for: type))")
        continue
    }

    let status = LSSetDefaultRoleHandlerForContentType(
        type as CFString, .viewer, bundleIdentifier as CFString
    )
    let now = currentHandler(for: type)
    if status == noErr, now.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
        print("\(type) -> \(now)")
    } else {
        print("\(type) -> \(now)  (LSSetDefaultRoleHandlerForContentType returned \(status))")
    }
}

if !statusOnly {
    print("""

    Done. If the Finder still shows the old application, it is caching the
    icon: relaunching the Finder or logging out refreshes it.
    """)
}
