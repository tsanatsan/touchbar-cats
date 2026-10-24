//
//  CatRenderer.swift
//  MTMR
//
//  Draws the cat scene: 1 sprite pixel = 1 pt, positions snapped to half points (Retina pixels).
//  Fireflies light up the fur around them, at night the scene dims and the eyes glow.
//

import AppKit
import CoreText

enum GlyphCache {
    private static var cache: [String: [(Int, Int)]] = [:]

    /// Pixels of a character rendered small and crisp, centered at (0, 0)
    static func pixels(_ ch: String) -> [(Int, Int)] {
        if let cached = cache[ch] { return cached }
        let size = 14
        var data = [UInt8](repeating: 0, count: size * size)
        var result: [(Int, Int)] = []
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            let font = CTFontCreateWithName("Menlo-Bold" as CFString, 11, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: ch, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
                                       y: (CGFloat(size) - bounds.height) / 2 - bounds.minY)
            CTLineDraw(line, ctx)
        }
        for row in 0 ..< size {
            for col in 0 ..< size where data[row * size + col] > 110 {
                result.append((col - 7, row - 7))
            }
        }
        cache[ch] = result
        return result
    }
}

private let nightTint = RGB(r: 6, g: 9, b: 26)
private let fireflyLight = RGB(r: 225, g: 255, b: 150)
private let rgbSpace = CGColorSpaceCreateDeviceRGB()

private func gradient(_ c: RGB, _ alpha: CGFloat) -> CGGradient {
    let colors = [CGColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: alpha),
                  CGColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 0)] as CFArray
    return CGGradient(colorsSpace: rgbSpace, colors: colors, locations: [0, 1])!
}

private let flyGlow = gradient(RGB(r: 214, g: 255, b: 120), 0.38)
private let floorGlow = gradient(RGB(r: 214, g: 255, b: 120), 0.12)
private var eyeGlows: [Int: CGGradient] = [:]

private struct Star {
    let x: CGFloat
    let y: CGFloat
    let phase: CGFloat
}

private let stars: [Star] = (0 ..< 90).map { _ in
    Star(x: .random(in: 0 ... 1), y: .random(in: 0 ... 0.55), phase: .random(in: 0 ... 6))
}

private func snap(_ v: CGFloat) -> CGFloat { return (v * 2).rounded() / 2 }

/// Sprite colors with coat pattern and outline, mirrored when a side-view cat faces left
func spriteScreen(_ cat: Cat, t: CGFloat, dark: CGFloat) -> (w: Int, h: Int, paints: [Paint?]) {
    let c = catPose(cat, t: t, dark: dark)
    let w = c.w, h = c.h
    var cols = [Paint?](repeating: nil, count: w * h)
    for y in 0 ..< h {
        for x in 0 ..< w {
            if let cell = c.cells[y * w + x] { cols[y * w + x] = coatPaint(cat, cell, x: x, y: y, canvas: c) }
        }
    }
    let flip = cat.mode != .front && cat.dir < 0
    var screen = [Paint?](repeating: nil, count: w * h)
    func solid(_ v: Paint?) -> Bool { return v != nil && v != .whisker }
    for y in 0 ..< h {
        for x in 0 ..< w {
            var k = cols[y * w + x]
            if k == nil {
                let n = (x > 0 && solid(cols[y * w + x - 1])) || (x < w - 1 && solid(cols[y * w + x + 1])) ||
                    (y > 0 && solid(cols[(y - 1) * w + x])) || (y < h - 1 && solid(cols[(y + 1) * w + x]))
                if n { k = .outline }
            }
            if let k = k { screen[y * w + (flip ? w - 1 - x : x)] = k }
        }
    }
    return (w, h, screen)
}

extension CatScene {
    func draw(in ctx: CGContext) {
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawSky(ctx)

        let lights = flies.filter { $0.alive && $0.isLit }.map { (x: $0.x, y: $0.y, a: $0.a) }
        for f in flies where !f.isLit { drawFly(f, ctx) }
        if let ball = ball, !ball.held { drawBall(ball, ctx) }
        let order = cats.sorted { a, b in
            let fa = a.mode == .front ? 1 + a.cl : 0, fb = b.mode == .front ? 1 + b.cl : 0
            return fa != fb ? fa < fb : a.jy < b.jy
        }
        for cat in order { drawCat(cat, lights: lights, ctx) }
        for f in flies where f.isLit { drawFly(f, ctx) }

        for s in sparks {
            ctx.setFillColor(red: 230 / 255, green: 1, blue: 150 / 255, alpha: s.life)
            ctx.fill(CGRect(x: snap(s.x), y: snap(s.y), width: 0.7, height: 0.7))
        }
        for d in dust {
            ctx.setFillColor(red: 200 / 255, green: 200 / 255, blue: 210 / 255, alpha: 0.35 * d.life)
            ctx.fill(CGRect(x: snap(d.x), y: snap(d.y), width: 0.8, height: 0.8))
        }
        for b in bubbles { drawBubble(b, ctx) }
        for e in effects { drawEffect(e, ctx) }
    }

    private func drawSky(_ ctx: CGContext) {
        guard dark > 0.05 else { return }
        let k = dark / 0.62
        for s in stars {
            ctx.setFillColor(red: 220 / 255, green: 230 / 255, blue: 1, alpha: (0.25 + 0.35 * sin(t * 1.3 + s.phase)) * k)
            ctx.fill(CGRect(x: snap(s.x * width), y: snap(1 + s.y * height), width: 0.6, height: 0.6))
        }
        ctx.setFillColor(red: 244 / 255, green: 236 / 255, blue: 200 / 255, alpha: k)
        let mx = width - 22, my: CGFloat = 4
        for y in 0 ..< 7 {
            for x in 0 ..< 7 {
                let d = pow(CGFloat(x) - 3, 2) + pow(CGFloat(y) - 3, 2)
                let d2 = pow(CGFloat(x) - 4.6, 2) + pow(CGFloat(y) - 2.2, 2)
                if d <= 10 && d2 > 7 { ctx.fill(CGRect(x: mx + CGFloat(x), y: my + CGFloat(y), width: 1, height: 1)) }
            }
        }
    }

    // MARK: - Cats

    private func drawCat(_ cat: Cat, lights: [(x: CGFloat, y: CGFloat, a: CGFloat)], _ ctx: CGContext) {
        let (w, h, screen) = spriteScreen(cat, t: t, dark: dark)
        let front = cat.mode == .front

        var sx: CGFloat, sy: CGFloat, left: CGFloat, top: CGFloat
        if front {
            let s = frontScale(cat)
            sx = s
            sy = s
            left = snap(cat.x) - CGFloat(w) / 2 * s
            let start = ground - CGFloat(h) * s * 0.98
            let hop: CGFloat = cat.cl > 0.02 && cat.cl < 0.98 ? -abs(sin(t * 12)) * 0.6 : 0
            top = snap(start + (-1 - start) * cat.cl + hop)
        } else {
            sx = cat.breed.size
            sy = cat.breed.size
            if cat.mode == .crouch {
                sx *= 1.06
                sy *= 0.9
            } else if cat.mode == .jump, let j = cat.jump, j.t < 0.45 {
                sx *= 0.93
                sy *= 1.1
            }
            if cat.land > 0 {
                let q = cat.land / 0.18
                sx *= 1 + 0.14 * q
                sy *= 1 - 0.18 * q
            }
            left = snap(cat.x) - CGFloat(w) / 2 * sx
            top = ground - CGFloat(h) * sy - snap(cat.jy)
            let shadow = max(0.4, 1 - cat.jy / 14)
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.05 * (1 - dark * 0.6))
            ctx.fillEllipse(in: CGRect(x: snap(cat.x) - 9 * sx * shadow, y: height - 2.1, width: 18 * sx * shadow, height: 2.2))
        }

        let reachLight: CGFloat = front ? 55 : 40
        let near = lights.filter { abs($0.x - cat.x) < 50 + CGFloat(w) * sx / 2 }
        var eyes: [(CGFloat, CGFloat, RGB)] = []
        func empty(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < w, y < h, let q = screen[y * w + x] else { return true }
            return q == .whisker
        }

        // the cat goes into a tiny bitmap and onto the bar with one draw call:
        // far cheaper than hundreds of rectangle fills per cat every frame
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0 ..< h {
            for x in 0 ..< w {
                guard let k = screen[y * w + x] else { continue }
                let wx = left + (CGFloat(x) + 0.5) * sx, wy = top + (CGFloat(y) + 0.5) * sy
                if wy - sy > height + 1 { continue }
                var amb: CGFloat = 0, rim: CGFloat = 0
                for l in near {
                    let vx = l.x - wx, vy = l.y - wy
                    let d = hypot(vx, vy) + 0.01
                    if d > reachLight { continue }
                    let i = l.a * (1 - d / reachLight)
                    amb += i
                    var best: CGFloat = 0
                    if empty(x - 1, y) { best = max(best, -vx / d) }
                    if empty(x + 1, y) { best = max(best, vx / d) }
                    if empty(x, y - 1) { best = max(best, -vy / d) }
                    if empty(x, y + 1) { best = max(best, vy / d) }
                    rim = max(rim, i * best)
                }
                amb = min(1, amb)
                let base = cat.breed.color(k)
                var col: RGB
                var alpha: CGFloat = 1
                switch k {
                case .eye, .eye2:
                    col = dark > 0 ? base.mixed(RGB(0xFFFFFF), 0.25) : (amb > 0.25 ? base.mixed(RGB(0xFFFFFF), 0.4) : base)
                    eyes.append((wx, wy, base))
                case .white:
                    col = base.mixed(nightTint, dark * 0.2)
                case .pupil:
                    col = base
                default:
                    col = base.mixed(nightTint, dark * (1 - 0.85 * amb))
                    col = col.mixed(fireflyLight, amb * 0.12)
                    col = col.mixed(fireflyLight, min(0.75, rim * 1.1))
                    if k == .whisker { alpha = 0.5 }
                }
                let i = (y * w + x) * 4 // premultiplied RGBA
                pixels[i] = UInt8(max(0, min(255, col.r * alpha)))
                pixels[i + 1] = UInt8(max(0, min(255, col.g * alpha)))
                pixels[i + 2] = UInt8(max(0, min(255, col.b * alpha)))
                pixels[i + 3] = UInt8(alpha * 255)
            }
        }
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: rgbSpace,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.translateBy(x: left, y: top + CGFloat(h) * sy) // the view is flipped, images are not
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w) * sx, height: CGFloat(h) * sy))
            ctx.restoreGState()
        }

        if dark > 0 && eyes.count < 20 {
            let r = 2.2 * min(sx, 1.2)
            for (ex, ey, color) in eyes {
                let key = Int(color.r) << 16 | Int(color.g) << 8 | Int(color.b)
                let g = eyeGlows[key] ?? gradient(color, 0.35)
                eyeGlows[key] = g
                ctx.saveGState()
                ctx.setAlpha(dark)
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: ex, y: ey), startRadius: 0, endCenter: CGPoint(x: ex, y: ey), endRadius: r, options: [])
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Fireflies, ball, bubbles, effects

    private func drawGlyph(_ f: Fly, color: RGB, alpha: CGFloat, dy: CGFloat, _ ctx: CGContext) {
        ctx.setFillColor(red: color.r / 255, green: color.g / 255, blue: color.b / 255, alpha: alpha)
        if f.glyph.isEmpty {
            ctx.fill(CGRect(x: snap(f.x), y: snap(f.y + dy), width: 1, height: 1))
            return
        }
        let p: CGFloat = 0.8
        ctx.saveGState()
        ctx.translateBy(x: f.x, y: f.y + dy)
        if f.rot != 0 { ctx.rotate(by: f.rot) }
        for (px, py) in f.glyph {
            ctx.fill(CGRect(x: CGFloat(px) * p, y: CGFloat(py) * p, width: p + 0.02, height: p + 0.02))
        }
        ctx.restoreGState()
    }

    private func drawFly(_ f: Fly, _ ctx: CGContext) {
        if f.isLit {
            let r: CGFloat = f.ch == nil ? 3.5 : 7
            ctx.saveGState()
            ctx.setAlpha(f.a)
            ctx.drawRadialGradient(flyGlow, startCenter: CGPoint(x: f.x, y: f.y), startRadius: 0,
                                   endCenter: CGPoint(x: f.x, y: f.y), endRadius: r, options: [])
            ctx.clip(to: CGRect(x: f.x - 14, y: height - 4, width: 28, height: 4))
            ctx.drawRadialGradient(floorGlow, startCenter: CGPoint(x: f.x, y: height - 1), startRadius: 0,
                                   endCenter: CGPoint(x: f.x, y: height - 1), endRadius: 14, options: [])
            ctx.restoreGState()
            if f.state == .rise {
                for k in 1 ... 3 {
                    drawGlyph(f, color: RGB(r: 214, g: 255, b: 120), alpha: 0.18 / CGFloat(k), dy: CGFloat(k) * 3, ctx)
                }
            }
            drawGlyph(f, color: RGB(r: 242, g: 255, b: 190), alpha: f.a, dy: 0, ctx)
        } else {
            drawGlyph(f, color: RGB(r: 190, g: 200, b: 185), alpha: f.state == .fall ? 0.4 : 0.85, dy: 0, ctx)
        }
    }

    private func drawBall(_ ball: YarnBall, _ ctx: CGContext) {
        let side: CGFloat = ball.vx < 0 ? -1 : 1
        let shade = RGB(0xF27A98).mixed(nightTint, dark * 0.6), deep = RGB(0xC84468).mixed(nightTint, dark * 0.6)
        ctx.setStrokeColor(red: 224 / 255, green: 90 / 255, blue: 122 / 255, alpha: 0.6 * (1 - dark * 0.5))
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: ball.x - side * 2.5, y: ball.y + 2.5))
        ctx.addQuadCurve(to: CGPoint(x: ball.x - side * 12, y: height - 1), control: CGPoint(x: ball.x - side * 7, y: height - 0.8))
        ctx.strokePath()
        for y in -3 ... 3 {
            for x in -3 ... 3 where x * x + y * y <= 10 {
                let stripe = Int((CGFloat(x) * cos(ball.rot) + CGFloat(y) * sin(ball.rot)).rounded()) % 2 == 0
                let c = stripe ? shade : deep
                ctx.setFillColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
                ctx.fill(CGRect(x: snap(ball.x) + CGFloat(x) - 0.5, y: snap(ball.y) + CGFloat(y) - 0.5, width: 1.02, height: 1.02))
            }
        }
    }

    private func drawBubble(_ b: Bubble, _ ctx: CGContext) {
        let cat = b.cat
        let pop = min(1, (b.total - b.life) * 8), fade = min(1, b.life * 3)
        let chars = b.text.map { String($0) }
        let sc: CGFloat = 0.62, adv = 6.2 * sc
        let w = CGFloat(chars.count) * adv + 4, h: CGFloat = 8
        let hx = cat.x + cat.dir * 7
        let x0 = max(1, min(width - w - 1, hx - w / 2)), y0: CGFloat = 1
        ctx.saveGState()
        ctx.setAlpha(fade)
        ctx.setFillColor(red: 244 / 255, green: 241 / 255, blue: 234 / 255, alpha: 1)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: y0, width: w * pop, height: h * pop), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        ctx.fillPath()
        ctx.fill(CGRect(x: hx - 1, y: y0 + h - 0.2, width: 2, height: 1.2))
        ctx.setFillColor(red: 42 / 255, green: 38 / 255, blue: 34 / 255, alpha: 1)
        for (i, ch) in chars.enumerated() {
            let cx = x0 + 2 + adv * (CGFloat(i) + 0.5), cy = y0 + h / 2
            for (px, py) in GlyphCache.pixels(ch) {
                ctx.fill(CGRect(x: cx + CGFloat(px) * sc, y: cy + CGFloat(py) * sc, width: sc + 0.02, height: sc + 0.02))
            }
        }
        ctx.restoreGState()
    }

    private static let sprites: [Effect.Kind: [String]] = [
        .heart: [".x.x.", "xxxxx", ".xxx.", "..x.."],
        .z: ["xxxx", "..x.", ".x..", "xxxx"],
        .bang: ["x", "x", "x", ".", "x"],
    ]

    private func drawEffect(_ e: Effect, _ ctx: CGContext) {
        let alpha = max(0, min(1, e.life * 1.5))
        switch e.kind {
        case .heart: ctx.setFillColor(red: 1, green: 122 / 255, blue: 168 / 255, alpha: alpha)
        case .z: ctx.setFillColor(red: 190 / 255, green: 210 / 255, blue: 1, alpha: alpha)
        case .bang: ctx.setFillColor(red: 1, green: 214 / 255, blue: 90 / 255, alpha: alpha)
        }
        let s: CGFloat = e.kind == .z ? 0.8 : 0.9
        for (ry, row) in (CatScene.sprites[e.kind] ?? []).enumerated() {
            for (rx, ch) in row.enumerated() where ch == "x" {
                ctx.fill(CGRect(x: snap(e.x + CGFloat(rx) * s), y: snap(e.y + CGFloat(ry) * s), width: s, height: s))
            }
        }
    }
}
