//
//  CatSprite.swift
//  MTMR
//
//  Pixel poses of a cat built from simple shapes, then colored by coat and outlined.
//  Side poses face right (mirrored when walking left), front pose faces the viewer.
//

import AppKit

let sideW = 30, sideH = 18, frontW = 28, frontH = 30

struct Cell {
    var paint: Paint
    var part: Part
}

final class SpriteCanvas {
    let w: Int
    let h: Int
    var cells: [Cell?]
    var hx = 0
    var hy = 0
    var noseX: CGFloat = 0
    let front: Bool

    init(w: Int, h: Int, front: Bool = false) {
        self.w = w
        self.h = h
        self.front = front
        cells = Array(repeating: nil, count: w * h)
    }

    func p(_ x: CGFloat, _ y: CGFloat, _ part: Part, _ paint: Paint = .fur) {
        let xi = Int(floor(x + 0.5)), yi = Int(floor(y + 0.5))
        guard xi >= 0, yi >= 0, xi < w, yi < h else { return }
        cells[yi * w + xi] = Cell(paint: paint, part: part)
    }

    func p(_ x: Int, _ y: Int, _ part: Part, _ paint: Paint = .fur) {
        p(CGFloat(x), CGFloat(y), part, paint)
    }

    func rect(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ part: Part, _ paint: Paint = .fur) {
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0 ... y1 {
            for x in x0 ... x1 { p(x, y, part, paint) }
        }
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ part: Part) {
        for y in Int(floor(cy - ry)) ... Int(ceil(cy + ry)) {
            for x in Int(floor(cx - rx)) ... Int(ceil(cx + rx)) {
                let q = pow((CGFloat(x) - cx) / rx, 2) + pow((CGFloat(y) - cy) / ry, 2)
                if q <= 1 { p(x, y, part) }
            }
        }
    }

    func triangle(_ a: CGPoint, _ b: CGPoint, _ q: CGPoint, _ part: Part, _ paint: Paint = .fur) {
        func side(_ x: CGFloat, _ y: CGFloat, _ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            return (x - p2.x) * (p1.y - p2.y) - (p1.x - p2.x) * (y - p2.y)
        }
        for y in Int(floor(min(a.y, b.y, q.y))) ... Int(ceil(max(a.y, b.y, q.y))) {
            for x in Int(floor(min(a.x, b.x, q.x))) ... Int(ceil(max(a.x, b.x, q.x))) {
                let fx = CGFloat(x), fy = CGFloat(y)
                let d1 = side(fx, fy, a, b), d2 = side(fx, fy, b, q), d3 = side(fx, fy, q, a)
                let neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0
                if !(neg && pos) { p(x, y, part, paint) }
            }
        }
    }

    func leg(_ x: Int, _ y0: Int, _ y1: Int) {
        rect(x, x, y0, y1 - 1, .leg)
        p(x, y1, .paw)
    }

    func tail(_ points: [CGPoint], thick: Bool) {
        guard points.count > 1 else { return }
        for i in 1 ..< points.count {
            let a = points[i - 1], b = points[i]
            let n = Int(ceil(hypot(b.x - a.x, b.y - a.y) * 1.5)) + 1
            let part: Part = i >= points.count - 2 ? .tailTip : .tail
            for k in 0 ... n {
                let x = a.x + (b.x - a.x) * CGFloat(k) / CGFloat(n)
                let y = a.y + (b.y - a.y) * CGFloat(k) / CGFloat(n)
                p(x, y, part)
                if thick {
                    p(x + 1, y, part)
                    p(x, y + 1, part)
                }
            }
        }
    }
}

/// Seasonal dress-up, set by the scene every frame
enum CatDecor {
    static var hats = false
}

enum EyeState {
    case open, up, wide, happy, closed
}

private func upTail(_ x0: CGFloat, _ y0: CGFloat, seed: CGFloat, t: CGFloat, length: Int, amp: CGFloat) -> [CGPoint] {
    var points = [CGPoint(x: x0, y: y0)]
    for i in 1 ... length {
        let fi = CGFloat(i)
        let sway = sin(t * 2.2 + seed + fi * 0.55) * amp * fi
        points.append(CGPoint(x: x0 - fi * 0.75 + sway * 0.4, y: y0 - fi * 0.95 + fi * fi * 0.035 + sway * 0.3))
    }
    return points
}

// MARK: - Side view

private func sideHead(_ c: SpriteCanvas, _ hx: Int, _ hy: Int, breed: Breed, eyes: EyeState,
                      mouth: Bool = false, twitch: Bool = false, carrying: Bool = false) {
    c.hx = hx
    c.hy = hy
    c.noseX = CGFloat(hx + 4)
    c.rect(hx + 1, hx + 5, hy, hy, .head)
    c.rect(hx, hx + 6, hy + 1, hy + 4, .head)
    c.rect(hx + 1, hx + 5, hy + 5, hy + 5, .head)

    switch breed.ears {
    case .folded:
        c.p(hx + 1, hy - 1, .ear)
        c.p(hx + 2, hy - 1, .ear)
        c.p(hx + 5, hy - 1, .ear)
    case .big:
        c.p(hx + 1, hy - 1, .ear)
        c.p(hx + 2, hy - 1, .earIn, .pink)
        c.p(hx + 1, hy - 2, .ear)
        c.p(hx + 2, hy - 2, .earIn, .pink)
        c.p(hx + 1, hy - 3, .ear)
        c.p(hx + 4, hy - 1, .earIn, .pink)
        c.p(hx + 5, hy - 1, .ear)
        c.p(hx + 5, hy - 2, .ear)
        c.p(hx + 5, hy - 3, .ear)
    case .normal, .tufted:
        c.p(hx + 1, hy - 1, .ear)
        c.p(hx + 2, hy - 1, .earIn, .pink)
        c.p(hx + 4, hy - 1, .earIn, .pink)
        c.p(hx + 5, hy - 1, .ear)
        c.p(hx + 1, hy - 2, .ear)
        if twitch { c.p(hx + 6, hy - 1, .ear) } else { c.p(hx + 5, hy - 2, .ear) }
        if breed.ears == .tufted {
            c.p(hx + 1, hy - 3, .tuft, .dark)
            if !twitch { c.p(hx + 5, hy - 3, .tuft, .dark) }
        }
    }
    c.rect(hx + 3, hx + 5, hy + 4, hy + 4, .muzzle)
    if CatDecor.hats { // a little Santa hat tilted back
        c.rect(hx + 1, hx + 5, hy - 1, hy - 1, .hat, .hatWhite)
        c.rect(hx + 1, hx + 4, hy - 2, hy - 2, .hat, .hatRed)
        c.rect(hx, hx + 2, hy - 3, hy - 3, .hat, .hatRed)
        c.p(hx - 1, hy - 3, .hat, .hatWhite)
    }

    switch eyes {
    case .open:
        c.p(hx + 2, hy + 2, .eye, .eye)
        c.p(hx + 5, hy + 2, .eye, .eye2)
    case .up:
        c.p(hx + 2, hy + 1, .eye, .eye)
        c.p(hx + 5, hy + 1, .eye, .eye2)
    case .wide:
        c.p(hx + 2, hy + 2, .eye, .eye)
        c.p(hx + 5, hy + 2, .eye, .eye2)
        c.p(hx + 2, hy + 1, .eye, .eye)
        c.p(hx + 5, hy + 1, .eye, .eye2)
    case .happy:
        c.p(hx + 2, hy + 1, .eyeClosed, .dark)
        c.p(hx + 5, hy + 1, .eyeClosed, .dark)
    case .closed:
        c.p(hx + 2, hy + 2, .eyeClosed, .dark)
        c.p(hx + 5, hy + 2, .eyeClosed, .dark)
    }
    c.p(hx + 4, hy + 3, .nose, .pink)
    if mouth {
        c.p(hx + 4, hy + 4, .mouth, .pink)
        c.p(hx + 4, hy + 5, .mouth, .pink)
        c.p(hx + 3, hy + 4, .mouth, .pink)
    }
    if carrying {
        c.p(hx + 6, hy + 4, .yarn, .yarnA)
        c.p(hx + 7, hy + 4, .yarn, .yarnB)
        c.p(hx + 6, hy + 5, .yarn, .yarnB)
        c.p(hx + 7, hy + 5, .yarn, .yarnA)
    }
}

private func sidePose(_ cat: Cat, t: CGFloat) -> SpriteCanvas {
    let c = SpriteCanvas(w: sideW, h: sideH)
    let b = cat.breed
    let fat = b.fat
    let frame = Int(cat.frame) % 4
    let twitch = cat.earT > 0
    let thick = b.tail == .bushy
    let seed = CGFloat(cat.seed)
    let tipTwitch: CGFloat = sin(t * 26) > 0 ? 1 : 0
    let blink = (t * 1000 + seed * 373).truncatingRemainder(dividingBy: 3700) < 130
    let baseEyes: EyeState = cat.happy > 0 ? .happy : (cat.look > 0 ? .up : (blink ? .closed : .open))

    switch cat.mode {
    case .walk, .run, .hunt, .attend, .come, .swatGo, .ballChase, .fetch, .carry, .enter, .exit, .boopGo,
         .eatGo, .boxGo, .warmGo, .laserChase, .mouseHunt:
        let bob = (cat.mode != .walk && cat.mode != .enter && frame % 2 == 1) ? 1 : 0
        let legTop: Int
        if fat {
            c.rect(8, 17, 9 + bob, 9 + bob, .body)
            c.rect(6, 19, 10 + bob, 13 + bob, .body)
            c.rect(7, 18, 14 + bob, 14 + bob, .belly)
            legTop = 15
        } else {
            c.rect(8, 17, 10 + bob, 10 + bob, .body)
            c.rect(7, 18, 11 + bob, 12 + bob, .body)
            c.rect(8, 17, 13 + bob, 13 + bob, .belly)
            legTop = 14
        }
        let a = [0, 1, 0, -1][frame], bb = -a
        c.leg(8 + a, legTop, a > 0 ? 16 : 17)
        c.leg(15 + a, legTop, a > 0 ? 16 : 17)
        c.leg(10 + bb, legTop, bb > 0 ? 16 : 17)
        c.leg(17 + bb, legTop, bb > 0 ? 16 : 17)
        sideHead(c, fat ? 18 : 17, (fat ? 4 : 5) + bob, breed: b, eyes: cat.mode == .hunt ? .up : baseEyes,
                 twitch: twitch, carrying: cat.carrying)
        let relaxed = cat.mode == .walk || cat.mode == .enter || cat.mode == .boopGo
        let tailY = CGFloat((fat ? 11 : 11) + bob)
        if relaxed {
            c.tail(upTail(fat ? 6 : 7, tailY, seed: seed, t: t, length: 7, amp: 0.12), thick: thick)
        } else {
            let tip = cat.mode == .hunt ? tipTwitch : 0
            c.tail([CGPoint(x: 7, y: tailY), CGPoint(x: 5, y: 10), CGPoint(x: 3, y: 10), CGPoint(x: 1, y: 9 + tip)], thick: thick)
        }

    case .crouch:
        let w = sin(t * 28) > 0 ? 1 : 0
        if fat {
            c.rect(8 + w, 17, 11, 11, .body)
            c.rect(6 + w, 19, 12, 15, .body)
            c.rect(7 + w, 18, 16, 16, .belly)
        } else {
            c.rect(8 + w, 17, 12, 12, .body)
            c.rect(7 + w, 18, 13, 14, .body)
            c.rect(8 + w, 17, 15, 15, .belly)
        }
        c.leg(8 + w, 16, 17)
        c.leg(10 + w, 16, 17)
        c.leg(16, 16, 17)
        c.leg(18, 16, 17)
        sideHead(c, 18, fat ? 8 : 9, breed: b, eyes: cat.prey != nil ? .up : .wide)
        c.tail([CGPoint(x: 7 + CGFloat(w), y: 13), CGPoint(x: 5, y: 13), CGPoint(x: 3, y: 12), CGPoint(x: 1, y: 13 - tipTwitch)], thick: thick)

    case .jump:
        if fat {
            c.rect(8, 17, 8, 8, .body)
            c.rect(6, 19, 9, 12, .body)
            c.rect(7, 18, 13, 13, .belly)
        } else {
            c.rect(8, 17, 9, 9, .body)
            c.rect(7, 18, 10, 11, .body)
            c.rect(8, 17, 12, 12, .belly)
        }
        c.rect(18, 20, 9, 9, .leg)
        c.p(21, 8, .paw)
        c.rect(19, 21, 10, 10, .leg)
        c.p(22, 9, .paw)
        c.rect(5, 7, 12, 12, .leg)
        c.p(4, 12, .paw)
        c.rect(4, 6, 13, 13, .leg)
        c.p(3, 13, .paw)
        sideHead(c, 18, 3, breed: b, eyes: .wide)
        c.tail([CGPoint(x: 7, y: 10), CGPoint(x: 5, y: 9), CGPoint(x: 3, y: 9), CGPoint(x: 1, y: 8)], thick: thick)

    case .loaf, .pomodoro, .warm:
        let breath: CGFloat = sin(t * 1.6 + seed) > 0 ? 0.35 : 0
        if fat {
            c.ellipse(13, 14.3, 8.4, 3.1 + breath, .body)
            c.rect(5, 21, 17, 17, .body)
        } else {
            c.ellipse(13, 14.6, 7.2, 2.6 + breath, .body)
            c.rect(7, 19, 17, 17, .body)
        }
        c.tail([CGPoint(x: 6, y: 14), CGPoint(x: 5, y: 16), CGPoint(x: 7, y: 17), CGPoint(x: 11, y: 17), CGPoint(x: 15, y: 17)], thick: thick)
        let loafEyes: EyeState = cat.happy > 0 || cat.mode == .warm ? .happy : .closed
        sideHead(c, fat ? 19 : 18, 10, breed: b, eyes: loafEyes, twitch: twitch)

    case .stretch:
        for x in 8 ... 18 {
            let top = Int((8 + CGFloat(x - 8) * 0.35).rounded())
            c.rect(x, x, top, top + (fat ? 4 : 3), x > 12 ? .belly : .body)
        }
        c.rect(9, 17, 9, 10, .body)
        c.leg(8, 12, 17)
        c.leg(10, 12, 17)
        c.rect(18, 23, 16, 16, .leg)
        c.p(24, 16, .paw)
        c.rect(19, 23, 17, 17, .leg)
        c.p(24, 17, .paw)
        sideHead(c, 20, 10, breed: b, eyes: .closed)
        c.tail(upTail(7, 9, seed: seed, t: t, length: 7, amp: 0.08), thick: thick)

    default: // sit, groom, yawn, munch, boop, swat, eat, wave, sulk, inBox
        let groom = cat.mode == .groom, yawn = cat.mode == .yawn, munch = cat.mode == .munch || cat.mode == .eat
        let swat = cat.mode == .swat, wave = cat.mode == .wave, sulk = cat.mode == .sulk
        let pawUp = groom && Int(t * 3) % 2 == 0
        let hd = groom ? 1 : 0
        if fat {
            c.ellipse(11, 14, 5.8, 3.8, .body)
            c.rect(13, 18, 9, 16, .body)
            c.rect(14, 17, 8, 8, .body)
            c.rect(15, 17, 10, 14, .chest)
        } else {
            c.ellipse(11, 14.2, 4.6, 3.4, .body)
            c.rect(13, 17, 9, 16, .body)
            c.rect(14, 16, 8, 8, .body)
            c.rect(15, 16, 10, 13, .chest)
        }
        c.leg(15, 12, 17)
        if pawUp {
            c.rect(18, 18, 8, 10, .leg)
            c.p(19, 8, .paw)
        } else if wave {
            let up = Int(t * 5) % 2 == 0 ? 0 : 1
            c.rect(18, 18, 6 + up, 10, .leg)
            c.p(18, 5 + up, .paw)
        } else if swat && cat.mt < 0.15 {
            c.rect(18, 18, 7, 10, .leg)
            c.p(18, 6, .paw)
        } else if swat && cat.mt < 0.38 {
            c.rect(18, 22, 13, 13, .leg)
            c.p(23, 13, .paw)
        } else {
            c.leg(17, 12, 17)
        }
        let eyes: EyeState = (yawn || groom || sulk) ? .closed : (munch || wave ? .happy : (swat ? .wide : baseEyes))
        let eatDown = cat.mode == .eat ? 2 : 0
        sideHead(c, 14 - hd + eatDown / 2, 2 + hd - (yawn ? 1 : 0) + eatDown, breed: b, eyes: eyes,
                 mouth: yawn || (munch && Int(t * 6) % 2 == 0), twitch: twitch)
        if pawUp { c.p(18, 8, .mouth, .pink) }
        let sw = CGFloat((sin(t * 1.8 + seed) * 1.2).rounded())
        c.tail([CGPoint(x: 7, y: 16), CGPoint(x: 4, y: 17), CGPoint(x: 2, y: 16), CGPoint(x: 1 + sw, y: 14), CGPoint(x: 1 + sw, y: 13)], thick: thick)
    }
    return c
}

// MARK: - Front view ("кс-кс": the cat comes up to the glass, so the face is drawn in more detail)

private func frontEar(_ c: SpriteCanvas, _ b: Breed, side: CGFloat, twitch: Bool) {
    func m(_ x: CGFloat) -> CGFloat { return side < 0 ? x : 27 - x }
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { return CGPoint(x: m(x), y: y) }
    switch b.ears {
    case .folded:
        c.rect(Int(min(m(7), m(10))), Int(max(m(7), m(10))), 5, 5, .ear)
        c.rect(Int(min(m(8), m(10))), Int(max(m(8), m(10))), 4, 4, .ear)
        c.p(m(9), 5, .earIn, .dark)
    case .big:
        c.triangle(pt(3.5, 11), pt(11.2, 5), pt(2.6, 0.4), .ear)
        c.triangle(pt(5, 9.4), pt(9.6, 5.9), pt(3.9, 2.6), .earIn, .pink)
    case .normal, .tufted:
        let tip: CGFloat = twitch && side > 0 ? 1.4 : 0.4
        c.triangle(pt(5.2, 9), pt(11.6, 5.4), pt(5.4, tip), .ear)
        c.triangle(pt(6.6, 7.6), pt(10, 6), pt(6.3, 2.6), .earIn, .pink)
        if b.ears == .tufted {
            c.p(m(5), 0, .tuft, .dark)
            c.p(m(4), 0, .tuft, .dark)
            c.p(m(7), 4, .tuftIn)
            c.p(m(8), 5, .tuftIn)
        }
    }
}

private func frontEye(_ c: SpriteCanvas, _ cat: Cat, side: CGFloat, dark: CGFloat, t: CGFloat) {
    let b = cat.breed
    let big = b.eyes == .big, almond = b.eyes == .almond
    let iris: Paint = side < 0 ? .eye : .eye2
    let ex: CGFloat = side < 0 ? (big || almond ? 9.5 : 9) : (big || almond ? 17.5 : 18)
    let wide = cat.cl > 0.6 || dark > 0.3
    let happy = cat.happy > 0 || cat.boopT > 0
    let blink = (t * 1000 + CGFloat(cat.seed) * 373).truncatingRemainder(dividingBy: 3300) < 120
    let ix = Int(ex) // integer column for round eyes

    if happy {
        if big {
            c.p(ex - 1.5, 13, .eyeClosed, .dark)
            c.p(ex - 0.5, 12, .eyeClosed, .dark)
            c.p(ex + 0.5, 12, .eyeClosed, .dark)
            c.p(ex + 1.5, 13, .eyeClosed, .dark)
        } else {
            c.p(ex - 1, 13, .eyeClosed, .dark)
            c.p(ex, 12, .eyeClosed, .dark)
            c.p(ex + 1, 13, .eyeClosed, .dark)
        }
        return
    }
    if blink {
        let hw: CGFloat = big || almond ? 1.5 : 1
        var x = ex - hw
        while x <= ex + hw + 0.01 {
            c.p(x, 12.5, .eyeClosed, .dark)
            x += 1
        }
        return
    }
    if big {
        let x0 = Int(floor(ex - 1.5 + 0.5)), x1 = Int(floor(ex + 1.5 + 0.5))
        c.rect(x0, x1, 10, 13, .eye, iris)
        c.p(x0, 10, .head)
        c.p(x1, 10, .head)
        c.p(x0, 13, .head)
        c.p(x1, 13, .head)
        if wide {
            c.rect(x0 + 1, x1 - 1, 10, 13, .pupil, .pupil)
            c.p(x0, 11, .pupil, .pupil)
            c.p(x1, 11, .pupil, .pupil)
        } else {
            c.rect(x0 + 1, x1 - 1, 11, 12, .pupil, .pupil)
        }
        c.p(x0 + 1, 11, .shine, .white)
        c.p(x1, 12, .shine, .white)
    } else if almond {
        let left = side < 0
        let x0 = Int(floor(ex - 1.5 + 0.5)) // 4 columns: x0...x0+3
        c.rect(x0, x0 + 2, left ? 11 : 12, left ? 11 : 12, .eye, iris)
        c.rect(x0 + 1, x0 + 3, left ? 12 : 11, left ? 12 : 11, .eye, iris)
        c.rect(x0, x0 + 2, left ? 12 : 11, left ? 12 : 11, .eye, iris)
        let px = CGFloat(Int(floor(ex + 0.5)))
        c.p(px, 11, .pupil, .pupil)
        c.p(px, 12, .pupil, .pupil)
        if wide { c.p(ex + (left ? 0.9 : -0.9), 11.5, .pupil, .pupil) }
        c.p(ex - 0.8, 11, .shine, .white)
    } else {
        c.rect(ix - 1, ix + 1, 11, 12, .eye, iris)
        c.p(ix, 13, .eye, iris)
        if wide {
            c.rect(ix - 1, ix, 11, 12, .pupil, .pupil)
            c.p(ix, 13, .pupil, .pupil)
        } else {
            c.rect(ix, ix, 11, 13, .pupil, .pupil)
        }
        c.p(ix - 1, 11, .shine, .white)
        if b.lids && cat.cl < 0.5 { c.rect(ix - 1, ix + 1, 11, 11, .eyeClosed, .dark) }
    }
}

private func frontPose(_ cat: Cat, t: CGFloat, dark: CGFloat) -> SpriteCanvas {
    let c = SpriteCanvas(w: frontW, h: frontH, front: true)
    let b = cat.breed
    c.hx = 4
    c.hy = 5
    c.noseX = 13.5
    let fat = b.fat, round = b.fat || b.ears == .folded
    let rx: CGFloat = b.coat == .skin ? 8.6 : (round ? 10.4 : 9.6)
    let ry: CGFloat = round ? 7.9 : 7.5
    let cy: CGFloat = 12.5
    let sw = (sin(t * 2 + CGFloat(cat.seed)) * 1.3).rounded()
    func r(_ v: CGFloat) -> Int { return Int(floor(v + 0.5)) }

    let bw: CGFloat = fat ? 11 : (b.coat == .skin ? 7.5 : 9)
    c.rect(r(13.5 - bw), r(13.5 + bw), 21, 29, .body)
    c.ellipse(13.5, 21.5, bw + 0.6, 3, .body)
    c.ellipse(13.5, 24.5, fat ? 5 : 3.8, 5, .chest)
    c.tail([CGPoint(x: CGFloat(r(13.5 + bw)), y: 28), CGPoint(x: CGFloat(r(15.5 + bw)), y: 27),
            CGPoint(x: CGFloat(r(16.5 + bw)), y: 25 + sw), CGPoint(x: CGFloat(r(16.5 + bw)), y: 22 + sw)],
           thick: b.tail == .bushy)
    if b.ruff {
        for y in 14 ... 23 {
            for x in 1 ... 26 {
                let q = pow((CGFloat(x) - 13.5) / (rx + 2.4), 2) + pow((CGFloat(y) - 17.8) / 6, 2)
                if q <= 1 && !(y >= 20 && (x * 7 + y * 3) % 4 == 0) { c.p(x, y, .ruff) }
            }
        }
    }
    frontEar(c, b, side: -1, twitch: cat.earT > 0)
    frontEar(c, b, side: 1, twitch: cat.earT > 0)
    c.ellipse(13.5, cy, rx, ry, .head)
    if fat { c.ellipse(13.5, cy + 3.2, rx + 0.9, 4.4, .head) }
    c.ellipse(13.5, 16.7, 3.7, 2.3, .muzzle)
    if CatDecor.hats {
        c.rect(6, 13, 3, 3, .hat, .hatWhite)
        c.rect(7, 12, 2, 2, .hat, .hatRed)
        c.rect(8, 11, 1, 1, .hat, .hatRed)
        c.rect(10, 12, 0, 0, .hat, .hatRed)
        c.p(13, 0, .hat, .hatWhite)
    }
    frontEye(c, cat, side: -1, dark: dark, t: t)
    frontEye(c, cat, side: 1, dark: dark, t: t)

    c.rect(12, 15, 15, 15, .nose, .pink)
    c.rect(13, 14, 16, 16, .nose, .pink)
    c.p(13, 17, .mouth, .dark)
    c.p(14, 17, .mouth, .dark)
    c.p(12, 18, .mouth, .dark)
    c.p(15, 18, .mouth, .dark)
    if cat.meowT > 0 { c.rect(13, 14, 18, 19, .mouth, .pink) }
    if cat.happy > 0 || cat.boopT > 0 {
        c.rect(6, 7, 16, 16, .blush, .pink)
        c.rect(20, 21, 16, 16, .blush, .pink)
    }
    if b.coat != .skin {
        for (x, y) in [(0, 14), (1, 14), (2, 15), (0, 17), (1, 17), (2, 17), (1, 20), (2, 19)] {
            c.p(x + 1, y, .whisker, .whisker)
            c.p(26 - x, y, .whisker, .whisker)
        }
    }
    if cat.pawT > 0 {
        // reaching to the glass: a paw with pink toe beans
        let up = min(1, cat.pawT * 3, (1.1 - cat.pawT) * 3)
        let py = CGFloat(r(28 - up * 10))
        c.ellipse(5.5, py, 3, 2.6, .paw)
        c.rect(4, 7, Int(py) + 2, 29, .leg)
        c.p(4, py - 1, .bean, .pink)
        c.p(5.5, py - 1.6, .bean, .pink)
        c.p(7, py - 1, .bean, .pink)
        c.rect(5, 6, Int(py) + 1, Int(py) + 1, .bean, .pink)
    }
    return c
}

func catPose(_ cat: Cat, t: CGFloat, dark: CGFloat) -> SpriteCanvas {
    return cat.mode == .front ? frontPose(cat, t: t, dark: dark) : sidePose(cat, t: t)
}

// MARK: - Coat colors

private func marks(_ list: [(Int, Int)]) -> Set<Int> {
    return Set(list.map { $0.1 * 100 + $0.0 })
}

private let tabbyFaceMarks = marks([(11, 8), (11, 7), (12, 6), (13, 7), (14, 7), (15, 6), (16, 7), (16, 8), (13, 5), (14, 5),
                                    (5, 14), (6, 14), (21, 14), (22, 14), (5, 16), (22, 16)])
private let skinFaceMarks = marks([(11, 7), (12, 6), (13, 7), (14, 7), (15, 6), (16, 7), (12, 9), (13, 8), (14, 8), (15, 9)])

func coatPaint(_ cat: Cat, _ cell: Cell, x: Int, y: Int, canvas c: SpriteCanvas) -> Paint {
    guard cell.paint == .fur else { return cell.paint }
    let part = cell.part
    let coat = cat.breed.coat
    let fx = CGFloat(x), fy = CGFloat(y)

    if part == .belly { return coat == .solid ? .fur : .belly }
    if part == .ruff { return coat == .tabby ? ((x + y) % 3 == 0 ? .fur : .belly) : .fur }
    if part == .tuftIn { return .belly }

    if c.front {
        if part == .head {
            switch coat {
            case .tabby where tabbyFaceMarks.contains(y * 100 + x): return .dark
            case .skin where skinFaceMarks.contains(y * 100 + x): return .dark
            case .tuxedo where y >= 10 && abs(fx - 13.5) <= (fy - 9.5) * 0.8: return .belly
            case .bicolor where y >= 7 && abs(fx - 13.5) <= 0.7 + (fy - 7) * 0.45: return .belly
            case .points where hypot(fx - 13.5, (fy - 15) * 1.15) < 5.2: return .dark
            case .calico where x <= 12 && y <= 11: return .dark
            case .calico where x >= 17 && y <= 9: return .patch
            default: break
            }
        }
        if part == .ear {
            if coat == .points { return .dark }
            if coat == .calico { return x < 13 ? .dark : .patch }
        }
        if part == .muzzle { return coat == .points ? .dark : (coat == .solid || coat == .skin ? .fur : .belly) }
        if part == .chest { return [.tuxedo, .bicolor, .calico, .tabby].contains(coat) ? .belly : .fur }
    }

    switch coat {
    case .tabby:
        if part == .tailTip { return .dark }
        if !c.front && (part == .body || part == .tail) && (x + (part == .tail ? y : 0)) % 3 == 0 { return .dark }
        if !c.front && part == .head && y == c.hy && x % 2 == 1 { return .dark }
        if part == .leg && y % 2 == 0 { return .dark }
        if part == .muzzle || part == .chest { return .belly }
    case .tuxedo, .bicolor:
        if part == .paw || part == .muzzle || part == .chest { return .belly }
    case .points:
        if [.ear, .tail, .tailTip, .paw, .muzzle].contains(part) { return .dark }
        if part == .leg && y >= c.h - 3 { return .dark }
        if !c.front && part == .head && abs(fx - c.noseX) <= 1.6 && y >= c.hy + 2 { return .dark }
    case .calico:
        if part == .paw || part == .muzzle || part == .chest { return .belly }
        let h = sin(Double((x >> 2) + cat.seed) * 12.99 + Double(y / 3) * 78.23) * 43758
        let r = h - floor(h)
        if r < 0.28 { return .dark }
        if r < 0.45 { return .patch }
    case .skin:
        if !c.front && part == .head && y == c.hy + 1 && x % 2 == 0 && abs(fx - c.noseX) <= 3 { return .dark }
        if part == .muzzle || part == .chest { return .belly }
    case .solid:
        break
    }
    return .fur
}
