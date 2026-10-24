//
//  CatLetterColor.swift
//  MTMR
//
//  The color of the typed letters: the glow around them, the trail, the sparks and the light on the cats' fur.
//  "Rainbow" gives every new letter the next color of the rainbow.
//

import AppKit

enum LetterColor: String, CaseIterable {
    case firefly, pink, blue, lilac, gold, mint, rainbow

    var title: String {
        switch self {
        case .firefly: return tr("Светлячок", "Firefly")
        case .pink: return tr("Розовый", "Pink")
        case .blue: return tr("Голубой", "Blue")
        case .lilac: return tr("Сиреневый", "Lilac")
        case .gold: return tr("Золотой", "Gold")
        case .mint: return tr("Мятный", "Mint")
        case .rainbow: return tr("Радуга", "Rainbow")
        }
    }

    private static var cached: LetterColor?

    /// Read once and kept: the renderer asks for it every frame
    static var current: LetterColor {
        get {
            if let c = cached { return c }
            let c = LetterColor(rawValue: UserDefaults.standard.string(forKey: "cats.letterColor") ?? "") ?? .firefly
            cached = c
            return c
        }
        set {
            cached = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "cats.letterColor")
        }
    }

    private static let rainbowColors: [RGB] = [RGB(0xFF6B6B), RGB(0xFFA94D), RGB(0xFFE066), RGB(0x69DB7C), RGB(0x4DABF7), RGB(0xB197FC)]

    /// The glow and the trail
    func glow(_ tint: Int) -> RGB {
        switch self {
        case .firefly: return RGB(r: 214, g: 255, b: 120)
        case .pink: return RGB(0xFF78B4)
        case .blue: return RGB(0x64C8FF)
        case .lilac: return RGB(0xB48CFF)
        case .gold: return RGB(0xFFC040)
        case .mint: return RGB(0x50E8B0)
        case .rainbow: return LetterColor.rainbowColors[tint % LetterColor.rainbowColors.count]
        }
    }

    /// The letter itself: its glow color, almost white
    func core(_ tint: Int) -> RGB {
        return self == .firefly ? RGB(r: 242, g: 255, b: 190) : glow(tint).mixed(RGB(0xFFFFFF), 0.62)
    }

    /// The light the letter casts on the fur
    func light(_ tint: Int) -> RGB {
        return self == .firefly ? RGB(r: 225, g: 255, b: 150) : glow(tint).mixed(RGB(0xFFFFFF), 0.4)
    }

    /// A round swatch for the menu
    var swatch: NSImage {
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let colors = self == .rainbow ? LetterColor.rainbowColors : [self.glow(0)]
            let step = 2 * CGFloat.pi / CGFloat(colors.count)
            for (i, c) in colors.enumerated() {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: rect.midX, y: rect.midY))
                path.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: 5.5,
                               startAngle: CGFloat(i) * step * 180 / .pi, endAngle: CGFloat(i + 1) * step * 180 / .pi)
                path.close()
                NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1).setFill()
                path.fill()
            }
            return true
        }
    }
}
