//
//  CatIcon.swift
//  MTMR
//
//  Pixel cat for the menu bar and the Control Strip button.
//  A template image: macOS tints it to match the menu bar, like system icons.
//

import AppKit

enum CatIcon {
    // a cat sitting with its tail curled up, eyes cut out
    private static let pattern = [
        "X...X........",
        "XX.XX........",
        "XXXXX........",
        "X.X.X........",
        "XXXXX........",
        ".XXX.........",
        ".XXXX........",
        "XXXXXX.....X.",
        "XXXXXXX....X.",
        "XXXXXXX...X..",
        "XXXXXXXX.X...",
        "XXXXXXXXX....",
        ".XXXXXXX.....",
    ]

    /// One pattern pixel = 1 pt, so it stays crisp on Retina
    static func image() -> NSImage {
        let size = NSSize(width: pattern[0].count, height: pattern.count)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in pattern.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TouchBar Cats"
        return image
    }
}
