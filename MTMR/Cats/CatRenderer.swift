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

    private static var images: [String: CGImage] = [:]

    /// The glyph as a tiny image in one color: a letter becomes one draw call instead of dozens of fills
    static func image(_ ch: String, _ color: RGB) -> CGImage? {
        let key = "\(ch)#\(color.key)"
        if let cached = images[key] { return cached }
        if images.count > 600 { images.removeAll() }
        let c = color.p3
        let px = 2, side = 14 * px // two device pixels per glyph pixel
        var data = [UInt8](repeating: 0, count: side * side * 4)
        for (gx, gy) in pixels(ch) {
            for dy in 0 ..< px {
                for dx in 0 ..< px {
                    let i = (((gy + 7) * px + dy) * side + (gx + 7) * px + dx) * 4
                    data[i] = UInt8(max(0, min(255, c.r)))
                    data[i + 1] = UInt8(max(0, min(255, c.g)))
                    data[i + 2] = UInt8(max(0, min(255, c.b)))
                    data[i + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: displaySpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        images[key] = image
        return image
    }
}

/// The Touch Bar draws in Display P3. Images made in the same space are composited as they are;
/// in any other space every pixel of every image would be converted on every frame.
let displaySpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

private var p3Cache: [Int: RGB] = [:]

extension RGB {
    var key: Int { return Int(r.rounded()) << 16 | Int(g.rounded()) << 8 | Int(b.rounded()) }

    /// The same color expressed in Display P3 (both share the sRGB curve, only the primaries differ)
    var p3: RGB {
        let k = key
        if let cached = p3Cache[k] { return cached }
        func linear(_ v: CGFloat) -> CGFloat {
            let c = v / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func encoded(_ v: CGFloat) -> CGFloat {
            let c = max(0, min(1, v))
            return 255 * (c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055)
        }
        let lr = linear(r), lg = linear(g), lb = linear(b)
        let out = RGB(r: encoded(0.8225 * lr + 0.1774 * lg),
                      g: encoded(0.0332 * lr + 0.9669 * lg),
                      b: encoded(0.0171 * lr + 0.0724 * lg + 0.9108 * lb))
        if p3Cache.count > 4000 { p3Cache.removeAll() }
        p3Cache[k] = out
        return out
    }
}

private let nightTint = RGB(r: 6, g: 9, b: 26)
private let nightTintP3 = nightTint.p3
private let rgbSpace = CGColorSpaceCreateDeviceRGB()

private func gradient(_ c: RGB, _ alpha: CGFloat) -> CGGradient {
    let colors = [CGColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: alpha),
                  CGColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 0)] as CFArray
    return CGGradient(colorsSpace: rgbSpace, colors: colors, locations: [0, 1])!
}

private var flyGlows: [Int: (fly: CGGradient, floor: CGGradient)] = [:]
private var eyeGlows: [Int: CGGradient] = [:]

private func glows(_ c: RGB) -> (fly: CGGradient, floor: CGGradient) {
    if let g = flyGlows[c.key] { return g }
    let g = (gradient(c, 0.38), gradient(c, 0.12))
    flyGlows[c.key] = g
    return g
}


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
        CatBackground.shared.draw(self, in: ctx, starfield: { [unowned self] c, k in self.drawStarfield(c, k) }, twinkle: { drawTwinkle(ctx) })
        drawExtrasBack(ctx)

        let theme = LetterColor.current
        let lights = flies.filter { $0.alive && $0.isLit }.map { (x: $0.x, y: $0.y, a: $0.a, c: theme.light($0.tint).p3) }
        for f in flies where !f.isLit { drawFly(f, theme, ctx) }
        if let ball = ball, !ball.held { drawBall(ball, ctx) }
        // a steady order: faces at the glass in front, cats in the air before those on the ground, otherwise
        // always the same, so overlapping cats never swap places from one frame to the next (that flickers)
        let order = cats.enumerated().sorted { a, b in
            let fa = a.element.mode == .front ? 1 + a.element.cl : 0, fb = b.element.mode == .front ? 1 + b.element.cl : 0
            if fa != fb { return fa < fb }
            let ja = a.element.jy > 0.5, jb = b.element.jy > 0.5
            if ja != jb { return jb }
            return a.offset < b.offset
        }.map { $0.element }
        for cat in order { drawCat(cat, lights: lights, ctx) }
        for f in flies where f.isLit { drawFly(f, theme, ctx) }
        drawExtrasFront(ctx)

        for (i, s) in sparks.enumerated() {
            let c = theme == .firefly ? RGB(r: 230, g: 255, b: 150) : theme.glow(i).mixed(RGB(0xFFFFFF), 0.35)
            ctx.setFillColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: s.life)
            ctx.fill(CGRect(x: snap(s.x), y: snap(s.y), width: 0.7, height: 0.7))
        }
        for d in dust {
            ctx.setFillColor(red: 200 / 255, green: 200 / 255, blue: 210 / 255, alpha: 0.35 * d.life)
            ctx.fill(CGRect(x: snap(d.x), y: snap(d.y), width: 0.8, height: 0.8))
        }
        for b in bubbles { drawBubble(b, ctx) }
        for e in effects { drawEffect(e, ctx) }
    }

    /// Stars and the moon at rest, baked into the night sky image
    private func drawStarfield(_ ctx: CGContext, _ k: CGFloat) {
        ctx.setFillColor(red: 220 / 255, green: 230 / 255, blue: 1, alpha: 0.3 * k)
        for s in stars {
            ctx.fill(CGRect(x: snap(s.x * width), y: snap(1 + s.y * height), width: 0.5, height: 0.5))
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

    /// A few stars sparkle on top of the baked ones every frame
    private func drawTwinkle(_ ctx: CGContext) {
        let k = dark / 0.62
        for s in stars.prefix(18) {
            let a = max(0, sin(t * 1.3 + s.phase)) * 0.35 * k
            guard a > 0.03 else { continue }
            ctx.setFillColor(red: 220 / 255, green: 230 / 255, blue: 1, alpha: a)
            ctx.fill(CGRect(x: snap(s.x * width), y: snap(1 + s.y * height), width: 0.5, height: 0.5))
        }
    }

    // MARK: - Cats

    private func drawCat(_ cat: Cat, lights: [(x: CGFloat, y: CGFloat, a: CGFloat, c: RGB)], _ ctx: CGContext) {
        if cat.mode != .front, let pack = CatPack.shared { // the close-up at the glass stays our own drawing
            drawPackCat(cat, pack, lights: lights, ctx)
            return
        }
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
        let palette = Paint.allCases.map { cat.breed.color($0).p3 } // one lookup per color, not per pixel
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0 ..< h {
            for x in 0 ..< w {
                guard let k = screen[y * w + x] else { continue }
                let wx = left + (CGFloat(x) + 0.5) * sx, wy = top + (CGFloat(y) + 0.5) * sy
                if wy - sy > height + 1 { continue }
                var amb: CGFloat = 0, rim: CGFloat = 0
                var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
                for l in near {
                    let vx = l.x - wx, vy = l.y - wy
                    let d = hypot(vx, vy) + 0.01
                    if d > reachLight { continue }
                    let i = l.a * (1 - d / reachLight)
                    amb += i
                    lr += l.c.r * i
                    lg += l.c.g * i
                    lb += l.c.b * i
                    var best: CGFloat = 0
                    if empty(x - 1, y) { best = max(best, -vx / d) }
                    if empty(x + 1, y) { best = max(best, vx / d) }
                    if empty(x, y - 1) { best = max(best, -vy / d) }
                    if empty(x, y + 1) { best = max(best, vy / d) }
                    rim = max(rim, i * best)
                }
                let light = amb > 0 ? RGB(r: lr / amb, g: lg / amb, b: lb / amb) : RGB(0xFFFFFF)
                amb = min(1, amb)
                let base = palette[k.rawValue]
                var col: RGB
                var alpha: CGFloat = 1
                switch k {
                case .eye, .eye2:
                    col = dark > 0 ? base.mixed(RGB(0xFFFFFF), 0.25) : (amb > 0.25 ? base.mixed(RGB(0xFFFFFF), 0.4) : base)
                    eyes.append((wx, wy, base))
                case .white:
                    col = base.mixed(nightTintP3, dark * 0.2)
                case .pupil:
                    col = base
                default:
                    col = base.mixed(nightTintP3, dark * (1 - 0.85 * amb))
                    col = col.mixed(light, amb * 0.12)
                    col = col.mixed(light, min(0.75, rim * 1.1))
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
           let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: displaySpace,
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

    // MARK: - The pack's cat

    /// Which frame of the pack's sheet shows what the cat is doing now, and whether its eyes are shut
    func packPose(_ cat: Cat) -> (row: Int, col: Int, shut: Bool) {
        let right = cat.dir >= 0
        func loop(_ a: PackAnim, speed: CGFloat = 1) -> (Int, Int) {
            return (right ? a.right : a.left, Int(cat.mt * a.fps * speed) % a.frames)
        }
        func once(_ a: PackAnim) -> (Int, Int) { // spread over the time the mode lasts
            let k = Int(cat.mt / max(0.05, cat.dur) * CGFloat(a.frames))
            return (right ? a.right : a.left, max(0, min(a.frames - 1, k)))
        }
        let blink = (t * 1000 + CGFloat(cat.seed) * 373).truncatingRemainder(dividingBy: 3700) < 130
        var shut = blink || cat.happy > 0
        var pose: (Int, Int)
        switch cat.mode {
        case .walk, .enter, .come, .boopGo, .eatGo, .boxGo, .warmGo, .swatGo, .carry:
            pose = loop(.walk, speed: cat.breed.speed)
        case .run, .hunt, .ballChase, .fetch, .attend, .laserChase, .mouseHunt, .exit:
            pose = loop(.run)
        case .laserCoast: // slowing down after the laser: the legs slow with the body, from a gallop to a walk
            let a: PackAnim = abs(cat.coast.v) > 40 ? .run : .walk
            pose = (right ? a.right : a.left, Int(cat.frame * 0.3) % a.frames)
        case .crouch:
            pose = loop(.stalk, speed: 2.4) // the wiggle before the leap
        case .jump: // push off, fly, stretch for the landing, touch down
            let k = cat.jump?.t ?? 0
            pose = (right ? PackAnim.jump.right : PackAnim.jump.left, k < 0.12 ? 0 : (k < 0.5 ? 1 : (k < 0.88 ? 2 : 3)))
        case .laserSwat:
            pose = once(.swat)
        case .laserClap:
            pose = once(.hindLegs)
        case .loaf, .pomodoro, .warm:
            pose = loop(.sleep)
            shut = true
        case .stretch:
            pose = (right ? PackAnim.stretchOut.right : PackAnim.stretchOut.left, 0)
            shut = true
        case .yawn:
            pose = once(.yawn)
            shut = true
        case .groom:
            pose = loop(.wash)
            shut = true
        case .munch:
            pose = loop(.munch)
        case .eat:
            pose = loop(.eat)
        case .wave:
            pose = once(.hindLegs)
        case .sulk:
            pose = (0, 1) // sitting with its back to us
        case .swat:
            pose = once(.swat)
        case .inBox:
            pose = (0, 0)
        default: // sit, boop, front: sitting sideways, looking where it faces
            pose = (0, right ? 3 : 2)
            if cat.meowT > 0 { pose = (PackAnim.meow.right, min(2, Int((0.6 - cat.meowT) * 6))) }
        }
        return (pose.0, pose.1, shut)
    }

    private func drawPackCat(_ cat: Cat, _ pack: CatPack, lights: [(x: CGFloat, y: CGFloat, a: CGFloat, c: RGB)], _ ctx: CGContext) {
        let pose = packPose(cat)
        guard let s = pack.sprite(cat.breed, row: pose.row, col: pose.col) else { return }
        let n = CatPack.cell
        var sx = cat.breed.size, sy = cat.breed.size
        if cat.land > 0 { // a squash on landing
            let q = cat.land / 0.18
            sx *= 1 + 0.1 * q
            sy *= 1 - 0.12 * q
        }
        let left = snap(cat.x) - CGFloat(n) / 2 * sx
        // the whole animation stands on one line, where its paws touch the ground: frames with the legs tucked
        // stay up instead of sinking, so a walk doesn't bob and a gallop leaves the ground
        // (row 0 holds different sitting poses side by side, each stands on its own)
        let base = pose.row == 0 ? s.bottom : pack.baseline(cat.breed, row: pose.row)
        let top = ground - CGFloat(base + 1) * sy - snap(cat.jy)
        let shadow = max(0.4, 1 - cat.jy / 14)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.05 * (1 - dark * 0.6))
        ctx.fillEllipse(in: CGRect(x: snap(cat.x) - 8 * sx * shadow, y: height - 2.1, width: 16 * sx * shadow, height: 2.2))

        var colors = s.colors // copied only when a hat goes on
        // a Santa hat on top of the head, tilted back
        if CatDecor.hats, let nose = s.nose {
            var headTop = n
            for x in max(0, nose.x - 3) ... min(n - 1, nose.x + 3) { for y in 0 ..< n where colors[y * n + x] != nil { headTop = min(headTop, y); break } }
            let back = pose.row == 0 && pose.col <= 1 || [20, 28, 32, 36, 52].contains(pose.row) ? -1 : (cat.dir >= 0 ? -1 : 1)
            let red = cat.breed.color(.hatRed).p3, white = cat.breed.color(.hatWhite).p3
            func put(_ x: Int, _ y: Int, _ c: RGB) {
                guard x >= 0, y >= 0, x < n, y < n else { return }
                colors[y * n + x] = UInt32(max(0, min(255, c.r))) << 16 | UInt32(max(0, min(255, c.g))) << 8 | UInt32(max(0, min(255, c.b)))
            }
            // white brim on the head, the red cap above it bending back, a white pompom at the tip
            let cx = nose.x, y0 = max(3, headTop)
            for dx in -2 ... 2 { put(cx + dx, y0, white) }
            for dx in -1 ... 1 { put(cx + dx, y0 - 1, red) }
            put(cx + back, y0 - 2, red)
            put(cx + back * 2, y0 - 2, red)
            put(cx + back * 3, y0 - 2, white)
        }

        let reachLight: CGFloat = 40
        let near = lights.filter { abs($0.x - cat.x) < 50 + CGFloat(n) * sx / 2 }
        func empty(_ x: Int, _ y: Int) -> Bool { return x < 0 || y < 0 || x >= n || y >= n || colors[y * n + x] == nil }
        let outline = cat.breed.color(.outline).p3
        var eyes: [(CGFloat, CGFloat, RGB)] = []
        // only the box around the cat (and its hat) becomes an image: a third of the cell
        let x0 = max(0, s.minX - 3), x1 = min(n - 1, s.maxX + 3), y0 = max(0, s.top - 3), y1 = s.bottom
        let bw = x1 - x0 + 1, bh = y1 - y0 + 1
        var pixels = [UInt8](repeating: 0, count: bw * bh * 4)
        for y in y0 ... y1 { for x in x0 ... x1 {
            guard let packed = colors[y * n + x] else { continue }
            var base = RGB(r: CGFloat(packed >> 16), g: CGFloat((packed >> 8) & 0xFF), b: CGFloat(packed & 0xFF))
            let wx = left + (CGFloat(x) + 0.5) * sx, wy = top + (CGFloat(y) + 0.5) * sy
            let isEye = s.eyes.contains(y * n + x)
            if isEye && pose.shut { base = outline }
            var amb: CGFloat = 0, rim: CGFloat = 0
            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
            for l in near {
                let vx = l.x - wx, vy = l.y - wy
                let d = hypot(vx, vy) + 0.01
                if d > reachLight { continue }
                let i = l.a * (1 - d / reachLight)
                amb += i
                lr += l.c.r * i
                lg += l.c.g * i
                lb += l.c.b * i
                var best: CGFloat = 0
                if empty(x - 1, y) { best = max(best, -vx / d) }
                if empty(x + 1, y) { best = max(best, vx / d) }
                if empty(x, y - 1) { best = max(best, -vy / d) }
                if empty(x, y + 1) { best = max(best, vy / d) }
                rim = max(rim, i * best)
            }
            let light = amb > 0 ? RGB(r: lr / amb, g: lg / amb, b: lb / amb) : RGB(0xFFFFFF)
            amb = min(1, amb)
            var col: RGB
            if isEye && !pose.shut {
                col = dark > 0 ? base.mixed(RGB(0xFFFFFF), 0.25) : (amb > 0.25 ? base.mixed(RGB(0xFFFFFF), 0.4) : base)
                eyes.append((wx, wy, base))
            } else {
                col = base.mixed(nightTintP3, dark * (1 - 0.85 * amb))
                col = col.mixed(light, amb * 0.12)
                col = col.mixed(light, min(0.75, rim * 1.1))
            }
            let i = ((y - y0) * bw + x - x0) * 4
            pixels[i] = UInt8(max(0, min(255, col.r)))
            pixels[i + 1] = UInt8(max(0, min(255, col.g)))
            pixels[i + 2] = UInt8(max(0, min(255, col.b)))
            pixels[i + 3] = 255
        } }
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let image = CGImage(width: bw, height: bh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bw * 4, space: displaySpace,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            ctx.saveGState()
            ctx.interpolationQuality = sx < 0.95 ? .medium : .none // kittens are scaled down smoothly, the rest stay crisp
            ctx.translateBy(x: left + CGFloat(x0) * sx, y: top + CGFloat(y1 + 1) * sy) // the view is flipped, images are not
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(bw) * sx, height: CGFloat(bh) * sy))
            ctx.restoreGState()
        }
        // the yarn ball in its mouth
        if cat.carrying, let nose = s.nose {
            let bx = left + (CGFloat(nose.x) + (cat.dir >= 0 ? 1.5 : -1.5)) * sx, by = top + (CGFloat(nose.y) + 2.5) * sy
            ctx.setFillColor(red: 0.95, green: 0.48, blue: 0.6, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: bx - 2, y: by - 2, width: 4, height: 4))
            ctx.setFillColor(red: 0.78, green: 0.27, blue: 0.41, alpha: 1)
            ctx.fill(CGRect(x: bx - 1, y: by - 0.5, width: 2, height: 0.6))
        }
        if dark > 0 && !eyes.isEmpty && eyes.count < 8 {
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
        guard let ch = f.ch, let image = GlyphCache.image(ch, color) else {
            ctx.setFillColor(red: color.r / 255, green: color.g / 255, blue: color.b / 255, alpha: alpha)
            ctx.fill(CGRect(x: snap(f.x), y: snap(f.y + dy), width: 1, height: 1))
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: f.x, y: f.y + dy)
        if f.rot != 0 { ctx.rotate(by: f.rot) }
        ctx.scaleBy(x: 1, y: -1) // the view is flipped, images are not
        ctx.setAlpha(alpha)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: -7, y: -7, width: 14, height: 14))
        ctx.restoreGState()
    }

    private func drawFly(_ f: Fly, _ theme: LetterColor, _ ctx: CGContext) {
        if f.isLit {
            let r: CGFloat = f.ch == nil ? 3.5 : 8.5
            let glow = theme.glow(f.tint)
            let (flyGlow, floorGlow) = glows(glow)
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
                    drawGlyph(f, color: glow, alpha: 0.18 / CGFloat(k), dy: CGFloat(k) * 3, ctx)
                }
            }
            drawGlyph(f, color: theme.core(f.tint), alpha: f.a, dy: 0, ctx)
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
