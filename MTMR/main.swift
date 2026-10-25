//
//  main.swift
//  MTMR
//

import Cocoa

CloudPack.runFromCommandLine() // the release build packs the cloud art with the app itself

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
