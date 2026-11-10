//
//  main.swift
//  MTMR
//

import Cocoa

applyAppLanguage() // macOS's own buttons follow the language chosen in the menu

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
