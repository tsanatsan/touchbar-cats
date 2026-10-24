//
//  CatBackground.swift
//  MTMR
//
//  Scenery behind the cats. Grass and a burgundy carpet fill the whole bar; the city and the beach are
//  views into the distance that follow the clock: dawn, morning, noon, afternoon, sunset, dusk and night,
//  with the sun crossing the bar. Each is drawn into two cached images (the sky, then everything in front
//  of the stars) and redrawn every ten minutes or when the width changes; only the sea glints move.
//

import AppKit

enum CatBackdrop: String, CaseIterable {
    case black, grass, carpet, city, beach

    var title: String {
        switch self {
        case .black: return tr("Чёрный", "Black")
        case .grass: return tr("Трава", "Grass")
        case .carpet: return tr("Ковёр", "Carpet")
        case .city: return tr("Город", "City")
        case .beach: return tr("Пляж", "Beach")
        }
    }

    static var current: CatBackdrop {
        get { return CatBackdrop(rawValue: UserDefaults.standard.string(forKey: "cats.background") ?? "") ?? .black }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "cats.background") }
    }

    /// Stars and the moon belong to the views with a sky
    var hasSky: Bool { return self == .black || self == .city || self == .beach }
}

private struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { return a + (b - a) * next() }
}

private struct Color {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }
    func mix(_ other: Color, _ k: CGFloat) -> Color {
        return Color(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }
    /// The day color dimmed toward its night version as daylight goes
    func by(_ light: CGFloat, night: Color) -> Color { return night.mix(self, light) }
}

/// The sky at a given hour, blended between keyframes
private struct SkyTime {
    let top: Color
    let horizon: Color
    let light: CGFloat // 0 night ... 1 noon
    let sun: (x: CGFloat, height: CGFloat)? // position along the bar 0...1, height above the horizon 0...1

    private static let keys: [(h: CGFloat, top: UInt32, horizon: UInt32, light: CGFloat)] = [
        (0, 0x070A18, 0x141C34, 0),
        (5.5, 0x070A18, 0x141C34, 0),
        (6.5, 0x1C2450, 0x6A4A72, 0.15), // first light
        (7.5, 0x3A5A96, 0xF2A274, 0.55), // dawn
        (9, 0x3E78BE, 0xA9CDE6, 0.9),
        (12, 0x2F7FD0, 0x9FD0F2, 1), // noon
        (15, 0x3A7EC6, 0xA8CCE4, 1),
        (17.5, 0x4A6FAE, 0xE8C090, 0.8), // golden hour
        (19.5, 0x2E2E66, 0xF07A48, 0.45), // sunset
        (21, 0x161A3E, 0x5A3458, 0.15), // dusk
        (22.5, 0x070A18, 0x141C34, 0),
        (24, 0x070A18, 0x141C34, 0),
    ]

    init(hour: CGFloat) {
        var i = 0
        while i < SkyTime.keys.count - 2 && SkyTime.keys[i + 1].h <= hour { i += 1 }
        let a = SkyTime.keys[i], b = SkyTime.keys[i + 1]
        let k = max(0, min(1, (hour - a.h) / max(0.01, b.h - a.h)))
        top = Color(a.top).mix(Color(b.top), k)
        horizon = Color(a.horizon).mix(Color(b.horizon), k)
        light = a.light + (b.light - a.light) * k
        let rise: CGFloat = 6.8, set: CGFloat = 20.2
        if hour > rise && hour < set {
            let p = (hour - rise) / (set - rise)
            sun = (p, sin(p * .pi))
        } else {
            sun = nil
        }
    }

    var sunColor: Color {
        return Color(0xFFF4C0).mix(Color(0xFF8A40), pow(1 - (sun?.height ?? 0), 2.5))
    }
}

final class CatBackground {
    static let shared = CatBackground()

    private var key = ""
    private var sky: CGImage?
    private var scenery: CGImage?
    private var glints: [(x: CGFloat, y: CGFloat, phase: CGFloat, bright: CGFloat)] = []

    private static let horizonY: CGFloat = 16 // where the sea meets the sky on the beach
    private static let shoreY: CGFloat = 25

    /// Hour of the day for the scenery: the clock, or fixed by "always night" / "always day"
    private func hour(_ scene: CatScene) -> CGFloat {
        if scene.nightMode == 1 { return 0 }
        if scene.nightMode == 2 { return 13 }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return CGFloat(c.hour ?? 12) + CGFloat(c.minute ?? 0) / 60
    }

    /// Draws the sky, then `stars` (the scene's stars and moon), then the scenery in front of them
    func draw(_ scene: CatScene, in ctx: CGContext, stars: () -> Void) {
        let kind = CatBackdrop.current
        guard kind != .black else {
            stars()
            return
        }
        let h = (hour(scene) * 6).rounded(.down) / 6 // ten-minute steps
        let newKey = "\(kind)-\(Int(scene.width))-\(h)"
        if newKey != key {
            key = newKey
            let time = SkyTime(hour: h)
            sky = render(scene.width, scene.height) { ctx, w, hh in self.drawSky(kind, time, ctx, w, hh) }
            scenery = render(scene.width, scene.height) { ctx, w, hh in self.drawScenery(kind, time, ctx, w, hh) }
        }
        blit(sky, ctx, scene.width, scene.height)
        if kind.hasSky { stars() }
        blit(scenery, ctx, scene.width, scene.height)
        if kind == .beach { drawGlints(scene.t, ctx) }
        fadeEdges(ctx, scene.width, scene.height)
    }

    // MARK: - Plumbing

    private func blit(_ image: CGImage?, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        guard let image = image else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: h) // the scene is drawn top-down
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    private func render(_ w: CGFloat, _ h: CGFloat, _ body: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage? {
        let scale: CGFloat = 2
        guard w > 0, let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: h * scale)
        ctx.scaleBy(x: scale, y: -scale) // top-down, like the scene
        body(ctx, w, h)
        return ctx.makeImage()
    }

    private let edgeFade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1])!

    /// The scenery fades into the black glass at both ends instead of stopping short
    private func fadeEdges(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        for (from, to) in [(CGFloat(0), CGFloat(10)), (w, w - 10)] {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: min(from, to), y: 0, width: 10, height: h))
            ctx.drawLinearGradient(edgeFade, start: CGPoint(x: from, y: 0), end: CGPoint(x: to, y: 0), options: [])
            ctx.restoreGState()
        }
    }

    private func fill(_ ctx: CGContext, _ c: Color, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ a: CGFloat = 1) {
        ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: a)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// A vertical gradient in device-pixel bands
    private func bands(_ ctx: CGContext, _ top: Color, _ bottom: Color, _ y0: CGFloat, _ y1: CGFloat, _ w: CGFloat) {
        var y = y0
        while y < y1 {
            fill(ctx, top.mix(bottom, (y - y0) / max(1, y1 - y0)), 0, y, w, 0.5)
            y += 0.5
        }
    }

    private func disc(_ ctx: CGContext, _ c: Color, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ a: CGFloat = 1) {
        var y = -r
        while y <= r {
            let half = (sqrt(max(0, r * r - y * y)) * 2).rounded() / 2
            fill(ctx, c, cx - half, cy + y, half * 2, 0.5, a)
            y += 0.5
        }
    }

    /// A pixel diamond: `r` steps out from the center, each step half a point
    private func diamond(_ ctx: CGContext, _ c: Color, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ a: CGFloat = 1) {
        var y = -r
        while y <= r {
            let half = r - abs(y)
            fill(ctx, c, cx - half - 0.25, cy + y - 0.25, half * 2 + 0.5, 0.5, a)
            y += 0.5
        }
    }

    // MARK: - Sky

    private func drawSky(_ kind: CatBackdrop, _ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        guard kind == .city || kind == .beach else { return }
        let horizon = kind == .beach ? CatBackground.horizonY : h - 3
        bands(ctx, time.top, time.horizon, 0, horizon, w)
        clouds(time, ctx, w, below: horizon - 3)
        if let sun = time.sun {
            let low = 1 - sun.height
            let color = time.sunColor
            let x = 24 + sun.x * (w - 48), y = horizon - 1 - sun.height * (horizon - 5)
            let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [CGColor(red: color.r, green: color.g, blue: color.b, alpha: 0.35),
                                           CGColor(red: color.r, green: color.g, blue: color.b, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y),
                                   endRadius: 14 + low * 10, options: [])
            disc(ctx, color, x, y, 3)
        }
        if kind == .beach { drawSea(time, ctx, w) }
    }

    /// Long flat clouds, white at noon, pink at sunset, barely there at night
    private func clouds(_ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, below: CGFloat) {
        var rng = Seeded(3)
        let color = Color(0xFFFFFF).mix(time.horizon, 0.45).by(0.3 + 0.7 * time.light, night: Color(0x2A3048))
        var x = rng.range(20, 80)
        while x < w {
            let y = rng.range(3, max(4, below - 6)), len = rng.range(18, 44)
            let a = 0.3 + 0.35 * time.light
            fill(ctx, color, x, y + 1, len, 1, a)
            fill(ctx, color, x + len * 0.15, y + 0.5, len * 0.5, 0.5, a)
            fill(ctx, color, x + len * 0.25, y, len * 0.25, 0.5, a * 0.8)
            fill(ctx, color.mix(Color(0x000000), 0.15), x + 2, y + 2, len - 4, 0.5, a * 0.6)
            x += rng.range(110, 240)
        }
    }

    // MARK: - Scenery

    private func drawScenery(_ kind: CatBackdrop, _ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        switch kind {
        case .black: break
        case .grass: drawGrass(time, ctx, w, h)
        case .carpet: drawCarpet(time, ctx, w, h)
        case .city: drawCity(time, ctx, w, h)
        case .beach: drawBeach(time, ctx, w, h)
        }
    }

    /// A lawn seen from above, filling the whole bar
    private func drawGrass(_ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = Seeded(5)
        let l = 0.35 + 0.65 * time.light
        let night = Color(0x0C1E12)
        fill(ctx, Color(0x2C5E2A).by(l, night: night), 0, 0, w, h)
        // soft patches of lighter and darker grass
        for _ in 0 ..< Int(w / 25) {
            let c = (rng.next() < 0.5 ? Color(0x24502A) : Color(0x3A7434)).by(l, night: night)
            let px = rng.range(0, w), py = rng.range(0, h), pw = rng.range(14, 40), ph = rng.range(5, 12)
            fill(ctx, c, px, py, pw, ph, 0.5)
            fill(ctx, c, px + 2, py - 1, pw - 4, 1, 0.5)
        }
        // blades: short strokes leaning this way and that, the brightest ones on top
        let shades = [Color(0x1E4A22), Color(0x2E6A30), Color(0x3E8A3A), Color(0x58A848), Color(0x76BE56)].map { $0.by(l, night: night) }
        for layer in 0 ..< shades.count {
            let count = Int(w * h / (layer < 2 ? 3 : 6))
            for _ in 0 ..< count {
                let x = (rng.range(0, w) * 2).rounded() / 2, y = (rng.range(-1, h) * 2).rounded() / 2
                let len = rng.range(1, 2.5)
                fill(ctx, shades[layer], x, y, 0.5, len)
                if rng.next() < 0.5 { fill(ctx, shades[layer], x + (rng.next() < 0.5 ? -0.5 : 0.5), y - 0.5, 0.5, 0.5) }
            }
        }
        // clover and daisies
        var x = rng.range(10, 40)
        while x < w {
            let fy = (rng.range(3, h - 3) * 2).rounded() / 2
            if rng.next() < 0.45 {
                let clover = Color(0x5CB050).by(l, night: night)
                for (dx, dy) in [(0.0, -0.5), (-0.5, 0.0), (0.5, 0.0)] as [(CGFloat, CGFloat)] { fill(ctx, clover, x + dx, fy + dy, 1, 1) }
            } else {
                let petal = (rng.next() < 0.7 ? Color(0xF4F4EC) : Color(0xF6D85A)).by(l, night: Color(0x283040))
                fill(ctx, petal, x - 0.5, fy, 1.5, 0.5)
                fill(ctx, petal, x, fy - 0.5, 0.5, 1.5)
                fill(ctx, Color(0xF0B830).by(l, night: Color(0x302A20)), x, fy, 0.5, 0.5)
            }
            x += rng.range(18, 60)
        }
    }

    /// A burgundy wall carpet, the kind every Soviet flat had: borders, a running pattern and medallions
    private func drawCarpet(_ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = Seeded(9)
        let l = 0.55 + 0.45 * time.light // indoors the lamp is on at night
        let dim = Color(0x140608)
        let red = Color(0x7E1A22).by(l, night: dim), deep = Color(0x5A1018).by(l, night: dim)
        let cream = Color(0xE2CC9A).by(l, night: dim), navy = Color(0x1E2C52).by(l, night: dim)
        let black = Color(0x1A0C0E).by(l, night: dim), gold = Color(0xC8902E).by(l, night: dim)
        fill(ctx, red, 0, 0, w, h)

        // borders top and bottom: a dark band, a cream thread and a row of little diamonds
        for top in [true, false] {
            let y0: CGFloat = top ? 0 : h - 5
            fill(ctx, black, 0, top ? y0 : y0 + 4, w, 1)
            fill(ctx, deep, 0, top ? y0 + 1 : y0, w, 4)
            fill(ctx, cream, 0, top ? y0 + 4.5 : y0, w, 0.5)
            var x: CGFloat = 2
            var odd = false
            while x < w {
                diamond(ctx, odd ? navy : cream, x, y0 + 2.5, 1.5)
                diamond(ctx, red, x, y0 + 2.5, 0.5)
                odd.toggle()
                x += 4.5
            }
        }

        // the field: big medallions with small crosses between them
        let cy = h / 2
        var x: CGFloat = 22
        var alt = false
        while x < w + 20 {
            diamond(ctx, black, x, cy, 9)
            diamond(ctx, cream, x, cy, 8.5)
            diamond(ctx, alt ? navy : deep, x, cy, 7.5)
            diamond(ctx, red, x, cy, 5.5)
            diamond(ctx, gold, x, cy, 4)
            diamond(ctx, alt ? deep : navy, x, cy, 3)
            diamond(ctx, cream, x, cy, 1.5)
            fill(ctx, red, x - 0.25, cy - 0.25, 0.5, 0.5)
            // hooks on the medallion's sides, the classic "rams' horns"
            for s in [-1, 1] as [CGFloat] {
                fill(ctx, cream, x + s * 10, cy - 0.25, 1.5 * s, 0.5)
                fill(ctx, cream, x + s * 11.5 - (s < 0 ? 0.5 : 0), cy - 1.5, 0.5, 1.25)
                fill(ctx, cream, x + s * 11.5 - (s < 0 ? 0.5 : 0), cy + 0.25, 0.5, 1.25)
            }
            // between medallions: a navy cross with a cream heart, and little stars above and below
            let mx = x + 20
            diamond(ctx, navy, mx, cy, 3.5)
            fill(ctx, navy, mx - 5, cy - 0.5, 10, 1)
            fill(ctx, navy, mx - 0.5, cy - 5, 1, 10)
            diamond(ctx, cream, mx, cy, 1)
            for dy in [-6.5, 6.5] as [CGFloat] {
                fill(ctx, cream, mx - 1, cy + dy - 0.25, 2, 0.5)
                fill(ctx, cream, mx - 0.25, cy + dy - 1, 0.5, 2)
            }
            alt.toggle()
            x += 40
        }

        // pile: tiny darker and lighter specks so it reads as wool, not paint
        for _ in 0 ..< Int(w * h / 5) {
            let px = (rng.range(0, w) * 2).rounded() / 2, py = (rng.range(0, h) * 2).rounded() / 2
            fill(ctx, rng.next() < 0.6 ? Color(0x000000) : Color(0xFFFFFF), px, py, 0.5, 0.5, 0.06)
        }
    }

    private func drawCity(_ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = Seeded(23)
        let l = time.light
        let lit = 0.1 + 0.6 * (1 - l) // share of lit windows
        let street = h - 3
        // three rows into the distance: towers lost in the haze, then closer and darker houses
        let rows: [(shade: Color, minH: CGFloat, maxH: CGFloat, windows: CGFloat, step: CGFloat)] = [
            (Color(0x9AACC4).by(l, night: Color(0x1C2236)).mix(time.horizon, 0.45), 14, 24, 0.35, 2.5),
            (Color(0x6C7C98).by(l, night: Color(0x141A2A)).mix(time.horizon, 0.2), 9, 19, 0.6, 3),
            (Color(0x3E4A62).by(l, night: Color(0x0A0C16)), 5, 13, 1, 3.5),
        ]
        for (row, r) in rows.enumerated() {
            var x: CGFloat = -rng.range(0, 16)
            while x < w {
                let bw = row == 0 ? rng.range(8, 18) : rng.range(14, 30)
                let bh = rng.range(r.minH, r.maxH)
                let top = street - bh
                fill(ctx, r.shade, x, top, bw, bh)
                fill(ctx, r.shade.mix(Color(0xFFFFFF), 0.1 * l), x, top, bw, 0.5) // the roof edge catching light
                let extra = rng.next()
                if row == 0 && extra < 0.15 {
                    fill(ctx, r.shade, x + bw / 2 - 0.25, top - 5, 0.5, 5) // a tall spire
                    fill(ctx, Color(0xFF4A3A), x + bw / 2 - 0.5, top - 5.5, 1, 1, 0.3 + 0.6 * (1 - l))
                } else if extra < 0.3 {
                    fill(ctx, r.shade, x + bw * 0.6, top - 3, 0.5, 3) // antenna
                } else if row > 0 && extra < 0.42 {
                    fill(ctx, r.shade, x + bw * 0.25, top - 2.5, 4, 2.5) // water tank
                }
                var wy = top + 1.5
                while wy < street - 1.5 {
                    var wx = x + 1.5
                    while wx < x + bw - 2 {
                        if rng.next() < lit {
                            let warm = Color(0xF2C46A).mix(Color(0xFFF0C8), rng.next() * 0.5)
                            fill(ctx, warm, wx, wy, row == 0 ? 1 : 1.5, 1, r.windows * (0.45 + 0.55 * (1 - l)))
                        } else if l > 0.3 && row > 0 {
                            fill(ctx, time.top.mix(Color(0xFFFFFF), 0.3), wx, wy, 1.5, 1, 0.2 * l) // glass reflecting the sky
                        }
                        wx += r.step
                    }
                    wy += r.step
                }
                x += bw + rng.range(0, row == 0 ? 8 : 4)
            }
            if row == 0 { // haze between the far towers and the rest
                fill(ctx, time.horizon, 0, street - 6, w, 6, 0.18)
            }
        }
        // the street, lamps lighting up after sunset
        fill(ctx, Color(0x55555F).by(l, night: Color(0x16161C)), 0, street, w, h - street)
        fill(ctx, Color(0x7A7A84).by(l, night: Color(0x26262E)), 0, street, w, 0.5)
        let on = max(0, 1 - l * 1.6)
        var x = rng.range(60, 120)
        while x < w {
            fill(ctx, Color(0x50505A).by(l, night: Color(0x22222A)), x, street - 12, 1, 12)
            fill(ctx, Color(0x50505A).by(l, night: Color(0x22222A)), x - 1, street - 12.5, 3, 1)
            if on > 0 {
                fill(ctx, Color(0xFFE6A0), x - 0.5, street - 11.5, 2, 1, on)
                fill(ctx, Color(0xFFE6A0), x - 6, street, 13, h - street, 0.14 * on)
            }
            x += rng.range(180, 300)
        }
    }

    private func drawSea(_ time: SkyTime, _ ctx: CGContext, _ w: CGFloat) {
        var rng = Seeded(41)
        let l = time.light
        let horizon = CatBackground.horizonY, shore = CatBackground.shoreY
        // far islands in the haze
        let island = Color(0x5E7E9A).by(l, night: Color(0x121A2C)).mix(time.horizon, 0.5)
        var x = rng.range(60, 200)
        while x < w {
            let iw = rng.range(30, 80), ih = rng.range(2, 4.5)
            var dx: CGFloat = 0
            while dx < iw {
                let k = dx / iw
                let top = horizon - ih * pow(sin(k * .pi), 0.7) - 0.4 * sin(dx / 3)
                fill(ctx, island, x + dx, top, 0.5, horizon - top)
                dx += 0.5
            }
            x += iw + rng.range(160, 360)
        }
        let far = time.horizon.mix(Color(0x1E5F96).by(l, night: Color(0x0A1430)), 0.6)
        let near = Color(0x3AA0B8).by(l, night: Color(0x0E1E36)).mix(time.horizon, 0.2)
        bands(ctx, far, near, horizon, shore, w)
        // a sailboat far away
        let sail = Color(0xF4F0E4).by(0.3 + 0.7 * l, night: Color(0x3A4058))
        let bx = w * 0.36
        fill(ctx, sail, bx, horizon - 3.5, 0.5, 3.5)
        fill(ctx, sail, bx + 0.5, horizon - 3, 1, 2.5)
        fill(ctx, sail, bx + 1.5, horizon - 2, 0.5, 1.5)
        fill(ctx, Color(0x4A3A30).by(l, night: Color(0x141420)), bx - 1, horizon - 0.5, 3.5, 0.5)
        // wave crests, longer as they come closer
        for row in [17.5, 19.0, 20.5, 22.0, 23.5] as [CGFloat] {
            var x = rng.range(0, 30)
            while x < w {
                let len = rng.range(2, 6) * (row / 19)
                fill(ctx, Color(0xFFFFFF), x, row, len, 0.5, 0.12 + 0.18 * l)
                x += rng.range(18, 50)
            }
        }
        // the sun's road on the water
        if let sun = time.sun {
            let x = 24 + sun.x * (w - 48)
            var y = horizon + 0.5
            while y < shore {
                let spread = 2 + (y - horizon) * 0.8
                fill(ctx, time.sunColor, x - spread / 2 + rng.range(-1, 1), y, spread * rng.range(0.4, 1), 0.5, 0.35)
                y += 1
            }
        }
        // glints twinkle every frame along the waves
        glints = (0 ..< 26).map { _ in
            (rng.range(0, w), rng.range(horizon + 1, shore - 0.5), rng.range(0, 6.28), 0.3 + 0.7 * l)
        }
    }

    private func drawGlints(_ t: CGFloat, _ ctx: CGContext) {
        for g in glints {
            let a = max(0, sin(t * 1.7 + g.phase)) * 0.55 * g.bright
            guard a > 0.05 else { continue }
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: a)
            ctx.fill(CGRect(x: g.x, y: g.y, width: 1, height: 0.5))
        }
    }

    private func drawBeach(_ time: SkyTime, _ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        var rng = Seeded(57)
        let l = 0.25 + 0.75 * time.light
        let sand = Color(0xE6CF98).by(l, night: Color(0x2E2A3A)).mix(time.horizon, 0.12)
        let wet = Color(0xB8A070).by(l, night: Color(0x24222E))
        let shore = CatBackground.shoreY
        fill(ctx, Color(0xFFFFFF), 0, shore - 0.5, w, 0.5, 0.25 + 0.25 * time.light) // foam
        fill(ctx, wet, 0, shore, w, 1)
        fill(ctx, sand, 0, shore + 1, w, h - shore - 1)
        // sand grains, shells and starfish
        for _ in 0 ..< Int(w / 6) {
            fill(ctx, sand.mix(Color(0x8A7048), 0.3), rng.range(0, w), rng.range(shore + 1.5, h - 0.5), 0.5, 0.5, 0.7)
        }
        var x = rng.range(40, 90)
        while x < w {
            if rng.next() < 0.3 {
                let star = Color(0xF08850).by(l, night: Color(0x3A2A30))
                fill(ctx, star, x - 1, h - 2, 2.5, 0.5)
                fill(ctx, star, x, h - 3, 0.5, 2)
                fill(ctx, star, x - 0.5, h - 1.5, 0.5, 0.5)
                fill(ctx, star, x + 1, h - 1.5, 0.5, 0.5)
            } else {
                fill(ctx, Color(0xF4E4E0).by(l, night: Color(0x3A3640)), x, h - 2, 1.5, 1)
                fill(ctx, Color(0xE0B8B0).by(l, night: Color(0x302C36)), x + 0.5, h - 2, 0.5, 1)
            }
            x += rng.range(70, 160)
        }
        for px in [w * 0.13, w * 0.58, w * 0.9] {
            palm(ctx, px + rng.range(-20, 20), h, l, lean: rng.next() < 0.5 ? -1 : 1)
        }
    }

    private func palm(_ ctx: CGContext, _ x: CGFloat, _ h: CGFloat, _ l: CGFloat, lean: CGFloat) {
        let trunk = Color(0x8A6A48).by(l, night: Color(0x1E1A1E))
        let leaf = Color(0x3E8A44).by(l, night: Color(0x0E1E18))
        var tx = x
        var y = h - 1
        while y > h - 19 {
            fill(ctx, trunk, tx, y - 1, 1.5, 1)
            if Int(y) % 3 == 0 { fill(ctx, trunk.mix(Color(0x000000), 0.25), tx, y - 1, 1.5, 0.5) }
            tx += lean * 0.12
            y -= 1
        }
        let cx = tx + 0.75, cy = y
        for (dx, droop) in [(-7.0, 3.5), (-4.5, 4.5), (4.5, 4.5), (7.0, 3.5), (-2, 2), (2, 2)] as [(CGFloat, CGFloat)] {
            var k: CGFloat = 0
            while k <= 1 {
                fill(ctx, leaf, cx + dx * k - 0.5, cy - 1 + droop * k * k - 1.2 * k, 1, 1)
                k += 0.12
            }
        }
        fill(ctx, Color(0x6A4A2A).by(l, night: Color(0x1A1414)), cx - 1, cy, 2, 1.5) // coconuts
    }
}
