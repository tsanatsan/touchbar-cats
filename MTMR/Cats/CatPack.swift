//
//  CatPack.swift
//  MTMR
//
//  The pixel cat from an art pack, worn by every breed. The pack's sheet holds one grey cat in 8 colors
//  (outline, fur, shadow, light, ear inside, pink, teeth, tongue) and hundreds of frames. Each frame is read
//  once: the thin places are ears, legs and the tail, the lowest pink is the nose, dark dots above it are the
//  eyes, the bottom rows are the paws. A breed's coat is laid out on those parts, its body reshaped (chubby,
//  big or folded ears, tufts, a ruff, no whiskers) and the pack's shading kept, so built-in cats, cats from
//  photos and kittens all wear the same well-drawn cat.
//
//  The art is licensed for use inside the app only: it is not in the repository. Without it the cats are
//  drawn the old way (CatSprite.swift).
//

import AppKit
import ImageIO

// MARK: - Animations

/// A row of the sheet: where the cat looks right and where it looks left (the same row for front views)
struct PackAnim {
    let right: Int
    let left: Int
    let frames: Int
    let fps: CGFloat

    static let sit = PackAnim(right: 0, left: 0, frames: 1, fps: 1) // the side sits are columns 3 and 2 of row 0
    static let walk = PackAnim(right: 6, left: 7, frames: 8, fps: 10)
    static let sleep = PackAnim(right: 13, left: 12, frames: 2, fps: 1.2)
    static let stretchOut = PackAnim(right: 19, left: 18, frames: 2, fps: 1)
    static let munch = PackAnim(right: 20, left: 20, frames: 8, fps: 9)
    static let eat = PackAnim(right: 23, left: 22, frames: 8, fps: 9)
    static let meow = PackAnim(right: 28, left: 28, frames: 3, fps: 6)
    static let yawn = PackAnim(right: 32, left: 32, frames: 8, fps: 8)
    static let wash = PackAnim(right: 36, left: 36, frames: 9, fps: 9)
    static let scratch = PackAnim(right: 40, left: 39, frames: 11, fps: 13)
    static let hiss = PackAnim(right: 42, left: 41, frames: 2, fps: 4)
    static let swat = PackAnim(right: 47, left: 46, frames: 7, fps: 12)
    static let hindLegs = PackAnim(right: 52, left: 52, frames: 4, fps: 6)
    static let stalk = PackAnim(right: 53, left: 54, frames: 4, fps: 5)
    static let jump = PackAnim(right: 55, left: 56, frames: 5, fps: 1)
    static let run = PackAnim(right: 57, left: 58, frames: 4, fps: 14)
}

/// One frame recolored for a breed: P3 colors (nil where empty), eye pixels, the nose, the feet
struct PackSprite {
    let colors: [UInt32?] // 32 x 32, 0xRRGGBB in Display P3
    let eyes: [Int] // pixel indices
    let nose: (x: Int, y: Int)?
    let top: Int // the highest and the lowest pixel row
    let bottom: Int
    let minX: Int // the leftmost and the rightmost pixel column
    let maxX: Int
}

// MARK: - The pack

final class CatPack {
    static let shared: CatPack? = CatPack()

    static let cell = 32
    private let sheetW: Int, sheetH: Int
    private let px: [UInt8]
    private var plain: [Int: PackFrame] = [:] // frames as drawn in the pack, read on first use
    private var shaped: [String: PackFrame] = [:] // reshaped for a body type
    private var sprites: [String: [Int: PackSprite]] = [:] // recolored per cat, until the cat changes

    private init?() {
        guard let url = Bundle.main.url(forResource: "CatBase", withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        sheetW = img.width
        sheetH = img.height
        var data = [UInt8](repeating: 0, count: sheetW * sheetH * 4)
        guard let ctx = CGContext(data: &data, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: sheetW * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
        px = data
    }

    var rows: Int { return sheetH / CatPack.cell }

    /// The frame of this breed, recolored and reshaped; kept until `forget` (a cat edited in the workshop)
    func sprite(_ breed: Breed, row: Int, col: Int) -> PackSprite? {
        let key = row * 64 + col
        if let s = sprites[breed.key]?[key] { return s }
        guard let frame = shapedFrame(breed, row: row, col: col) else { return nil }
        let s = paint(frame, breed)
        if (sprites[breed.key]?.count ?? 0) > 400 { sprites[breed.key] = [:] }
        sprites[breed.key, default: [:]][key] = s
        return s
    }

    /// The cat's colors or shape changed: its frames are painted again
    func forget(_ key: String) {
        sprites[key] = nil
        baselines[key] = nil
    }

    private var baselines: [String: [Int: Int]] = [:]

    /// The lowest pixel of a whole row of frames: where that animation's paws meet the ground
    func baseline(_ breed: Breed, row: Int) -> Int {
        if let b = baselines[breed.key]?[row] { return b }
        var lowest = 0
        for col in 0 ..< 12 {
            guard let s = sprite(breed, row: row, col: col), s.bottom >= s.top else { continue }
            lowest = max(lowest, s.bottom)
        }
        baselines[breed.key, default: [:]][row] = lowest
        return lowest
    }

    private func shapedFrame(_ b: Breed, row: Int, col: Int) -> PackFrame? {
        let body = "\(b.fat)|\(b.ears)|\(b.ruff)|\(b.coat == .skin)|\(row)|\(col)"
        if let f = shaped[body] { return f }
        let key = row * 64 + col
        if plain[key] == nil {
            guard let f = PackFrame(px: px, sheetW: sheetW, x0: col * CatPack.cell, y0: row * CatPack.cell, row: row) else { return nil }
            plain[key] = f
        }
        guard var f = plain[key] else { return nil }
        if b.fat { f.fatten() }
        if b.ears != .normal { f.shapeEars(b.ears) }
        if b.ruff { f.addRuff() }
        if b.coat == .skin { f.removeWhiskers() }
        shaped[body] = f
        return f
    }

    // MARK: - Colors

    private func paint(_ f: PackFrame, _ b: Breed) -> PackSprite {
        let n = CatPack.cell
        var colors = [UInt32?](repeating: nil, count: n * n)
        var eyes: [Int] = []
        let outline = b.color(.outline), pink = b.color(.pink)
        let eye = b.color(.eye), eye2 = b.palette[.eye2]
        func pack(_ c: RGB) -> UInt32 {
            let p = c.p3
            return UInt32(max(0, min(255, p.r))) << 16 | UInt32(max(0, min(255, p.g))) << 8 | UInt32(max(0, min(255, p.b)))
        }
        var top = n, bottom = 0, minX = n, maxX = 0
        for y in 0 ..< n { for x in 0 ..< n {
            let i = y * n + x
            guard let role = f.roles[i] else { continue }
            top = min(top, y)
            bottom = max(bottom, y)
            minX = min(minX, x)
            maxX = max(maxX, x)
            let c: RGB
            switch role {
            case .outline:
                if f.parts[i] == .eye {
                    eyes.append(i)
                    if let e2 = eye2, let nose = f.nose, x > nose.x { c = e2 } else { c = eye }
                } else {
                    c = outline
                }
            case .fur: c = coat(b, f, x, y)
            case .shadow: c = coat(b, f, x, y).mixed(outline, 0.32)
            case .light: c = coat(b, f, x, y).mixed(RGB(0xFFFFFF), 0.3)
            case .earIn: c = pink.mixed(coat(b, f, x, y), 0.45)
            case .pink: c = pink
            case .teeth: c = RGB(0xF6F2EC)
            case .tongue: c = RGB(0xF4A0B2)
            case .other: c = b.color(.fur)
            }
            colors[i] = pack(c)
        } }
        return PackSprite(colors: colors, eyes: eyes, nose: f.nose, top: top, bottom: bottom, minX: minX, maxX: maxX)
    }

    /// Smooth value noise on a 6-pixel grid, 0...1: calico patches that stay put on the body from frame to frame
    private static func patchNoise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        func h(_ i: Int, _ j: Int) -> CGFloat { let v = sin(CGFloat(i * 127 + j * 311) * 12.9898 + 78.233) * 43758.5453; return v - floor(v) }
        let gx = x / 6, gy = y / 6, i = Int(floor(gx)), j = Int(floor(gy))
        let fx = gx - CGFloat(i), fy = gy - CGFloat(j)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let top = h(i, j) + (h(i + 1, j) - h(i, j)) * sx, bottom = h(i, j + 1) + (h(i + 1, j + 1) - h(i, j + 1)) * sx
        return top + (bottom - top) * sy
    }

    /// The coat color under a fur pixel, before the pack's shading
    private func coat(_ b: Breed, _ f: PackFrame, _ x: Int, _ y: Int) -> RGB {
        let part = f.parts[y * CatPack.cell + x]
        let fur = b.color(.fur), dark = b.color(.dark), belly = b.color(.belly)
        switch b.coat {
        case .solid:
            return fur
        case .tabby:
            if part == .muzzle || part == .chest { return belly }
            if part == .face, let n = f.nose, y < n.y - 3, (x - n.x) % 2 == 0 { return dark } // the "M" on the forehead
            if part == .face { return fur }
            if part == .extremity || part == .paw { return y % 2 == 0 ? dark : fur } // ringed legs and tail
            return (x + y / 2) % 3 == 0 ? dark : fur
        case .tuxedo, .bicolor:
            if part == .muzzle || part == .chest || part == .paw { return belly }
            if b.coat == .bicolor, let n = f.nose, part == .face, y >= n.y - 3, abs(x - n.x) <= (y - (n.y - 3)) / 2 { return belly } // the blaze
            return fur
        case .calico:
            if part == .muzzle || part == .chest || part == .paw { return belly }
            let v = CatPack.patchNoise(CGFloat(x), CGFloat(y))
            if v < 0.36 { return dark }
            if v > 0.68 { return b.palette[.patch] ?? dark }
            return fur
        case .points:
            if part == .ear || part == .extremity || part == .paw { return dark }
            if let n = f.nose, part == .face || part == .muzzle {
                let d = hypot(CGFloat(x - n.x), CGFloat(y - n.y) * 1.2)
                if d < 2.6 { return dark }
                if d < 3.6 { return fur.mixed(dark, 0.5) }
            }
            return fur
        case .skin:
            if part == .muzzle || part == .chest { return belly }
            if let n = f.nose, part == .face, y == n.y - 4, abs(x - n.x) <= 2, x % 2 == 0 { return dark } // forehead wrinkles
            return fur
        }
    }
}

// MARK: - One frame read from the sheet

private enum PackRole { case outline, fur, shadow, light, earIn, pink, teeth, tongue, other }
private enum PackPart { case none, body, extremity, paw, ear, muzzle, chest, eye, nose, face }
private enum PackView { case front, side, back }

private let packRoles: [UInt32: PackRole] = [
    0x120E14: .outline, 0x626773: .fur, 0x414752: .shadow, 0x868D9B: .light,
    0x9A877E: .earIn, 0xCA719F: .pink, 0xE1DEE7: .teeth, 0xE197C6: .tongue,
]

/// Which way the cat looks in each row of the sheet
private let rowDirs: [String] = [
    "mixed", "mixed", "mixed", "mixed", "down", "up", "right", "left", "left", "right", "right", "left",
    "left", "right", "left", "right", "left", "right", "left", "right",
    "down", "up", "left", "right", "right", "left", "right", "left",
    "down", "down", "down", "down", "down", "down", "down", "down", "down", "down", "down", "down", "down",
    "left", "right", "down", "down", "up", "left", "right", "right", "left", "right", "left", "down",
    "right", "left", "right", "left", "right", "left",
]

private struct PackFrame {
    var view = PackView.front
    var roles: [PackRole?]
    var parts: [PackPart]
    var nose: (x: Int, y: Int)?

    private static let n = CatPack.cell

    init?(px: [UInt8], sheetW: Int, x0: Int, y0: Int, row: Int) {
        let n = PackFrame.n
        roles = [PackRole?](repeating: nil, count: n * n)
        parts = [PackPart](repeating: .none, count: n * n)
        var any = false
        for y in 0 ..< n { for x in 0 ..< n {
            let i = ((y0 + y) * sheetW + x0 + x) * 4
            guard i + 3 < px.count, px[i + 3] > 0 else { continue }
            let k = UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2])
            roles[y * n + x] = packRoles[k] ?? .other
            any = true
        } }
        guard any else { return nil }
        analyze(row: row)
    }

    func solid(_ x: Int, _ y: Int) -> Bool {
        let n = PackFrame.n
        return x >= 0 && y >= 0 && x < n && y < n && roles[y * n + x] != nil
    }

    func role(_ x: Int, _ y: Int) -> PackRole? {
        let n = PackFrame.n
        return x < 0 || y < 0 || x >= n || y >= n ? nil : roles[y * n + x]
    }

    var box: (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let n = PackFrame.n
        var b = (n, n, -1, -1)
        for y in 0 ..< n { for x in 0 ..< n where solid(x, y) { b = (min(b.0, x), min(b.1, y), max(b.2, x), max(b.3, y)) } }
        return b
    }

    mutating func set(_ x: Int, _ y: Int, _ r: PackRole?, _ p: PackPart) {
        let n = PackFrame.n
        guard x >= 0, y >= 0, x < n, y < n else { return }
        roles[y * n + x] = r
        parts[y * n + x] = p
    }

    func at(_ x: Int, _ y: Int) -> (PackRole?, PackPart) {
        let n = PackFrame.n
        guard x >= 0, y >= 0, x < n, y < n else { return (nil, .none) }
        return (roles[y * n + x], parts[y * n + x])
    }

    // MARK: Reading the parts

    private mutating func analyze(row: Int) {
        let n = PackFrame.n
        // how thick the cat is through each pixel: the shorter of its horizontal and vertical runs
        var thick = [Int](repeating: 0, count: n * n)
        var bottom = 0
        for y in 0 ..< n { for x in 0 ..< n where solid(x, y) {
            var l = x, r = x, u = y, d = y
            while solid(l - 1, y) { l -= 1 }
            while solid(r + 1, y) { r += 1 }
            while solid(x, u - 1) { u -= 1 }
            while solid(x, d + 1) { d += 1 }
            thick[y * n + x] = min(r - l + 1, d - u + 1)
            bottom = max(bottom, y)
        } }

        // the nose: the lowest pink pixel inside fur (ear insides sit at the top edge); a mouth is below it
        var best: (Int, Int)?
        for y in 0 ..< n { for x in 0 ..< n where [.pink, .teeth, .tongue].contains(role(x, y)) {
            let inside = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { solid(x + $0.0, y + $0.1) }.count == 4
            if inside && thick[y * n + x] >= 4, best == nil || y > best!.1 { best = (x, y) }
        } }
        if let b = best {
            var top = b
            for y in max(0, b.1 - 3) ..< b.1 { for x in max(0, b.0 - 1) ... min(n - 1, b.0 + 1) where role(x, y) == .pink { if y < top.1 { top = (x, y) } } }
            nose = (top.0, top.1)
        }

        for y in 0 ..< n { for x in 0 ..< n where solid(x, y) {
            let i = y * n + x
            parts[i] = thick[i] <= 3 ? (y >= bottom - 2 ? .paw : .extremity) : .body
        } }

        let dir = row < rowDirs.count ? rowDirs[row] : "mixed"
        switch dir {
        case "left", "right": view = .side
        case "up": view = .back
        case "down": view = nose == nil ? .back : .front
        default:
            if let nz = nose {
                let b = box
                view = abs(CGFloat(nz.x) - CGFloat(b.minX + b.maxX) / 2) <= 2.5 ? .front : .side
            } else {
                view = .back
            }
        }

        // ears: small sharp pieces on top of the head; a raised tail is thin too, but long
        let headTop = (0 ..< n * n).filter { thick[$0] >= 4 && solid($0 % n, $0 / n) }.map { $0 / n }.min() ?? 0
        var seen = Set<Int>()
        for start in 0 ..< n * n where parts[start] == .extremity && !seen.contains(start) {
            var piece: [Int] = [], queue = [start]
            seen.insert(start)
            while let i = queue.popLast() {
                piece.append(i)
                let x = i % n, y = i / n
                for dy in -1 ... 1 { for dx in -1 ... 1 {
                    let nx = x + dx, ny = y + dy, j = ny * n + nx
                    guard nx >= 0, ny >= 0, nx < n, ny < n, parts[j] == .extremity, !seen.contains(j) else { continue }
                    seen.insert(j)
                    queue.append(j)
                } }
            }
            let xs = piece.map { $0 % n }, ys = piece.map { $0 / n }
            let sitsOnBody = piece.contains { i in let x = i % n, y = i / n; return y + 1 < n && thick[(y + 1) * n + x] >= 4 && solid(x, y + 1) }
            if ys.max()! - ys.min()! < 4 && xs.max()! - xs.min()! < 5 && piece.count <= 12 && sitsOnBody && ys.max()! <= headTop + 1 {
                for i in piece { parts[i] = .ear }
            }
        }

        guard let nz = nose else { return }
        let b = box
        let towardBody = CGFloat(nz.x) < CGFloat(b.minX + b.maxX) / 2 ? 1 : -1 // from the side the body is behind the nose
        for y in 0 ..< n { for x in 0 ..< n where solid(x, y) {
            let i = y * n + x, dx = x - nz.x, dy = y - nz.y
            if abs(dx) <= 4 && dy >= -4 && dy <= 2 && parts[i] != .ear { parts[i] = .face }
            if abs(dx) <= 1 && dy >= 0 && dy <= 2 { parts[i] = .muzzle }
            if view == .side {
                if dx * towardBody >= 0 && dx * towardBody <= 3 && dy >= 2 && dy <= 5 && parts[i] == .body { parts[i] = .chest }
            } else if abs(dx) <= 2 && dy >= 3 && dy <= 7 && parts[i] == .body { parts[i] = .chest }
            // eyes: dark dots inside the face, above the nose
            if role(x, y) == .outline && dy >= -3 && dy <= -1 && abs(dx) >= 1 && abs(dx) <= 4 {
                let around = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { q in let v = role(x + q.0, y + q.1); return v != nil && v != .outline }.count
                if around >= 3 { parts[i] = .eye }
            }
        } }
        parts[nz.y * n + nz.x] = .nose
    }

    // MARK: Body shapes

    /// Chubby: from the front the belly spreads to both sides, from the side it sags between the legs
    mutating func fatten() {
        let n = PackFrame.n
        let b = box
        guard b.maxY > b.minY else { return }
        if view != .side {
            let cx = nose?.x ?? (b.minX + b.maxX) / 2
            let y0 = (nose?.y ?? b.minY + 6) + 3, y1 = b.maxY
            guard y1 > y0 else { return }
            for y in y0 ... y1 {
                let t = CGFloat(y - y0) / CGFloat(y1 - y0)
                let k = t < 0.08 ? 0 : (t < 0.3 || t > 0.85 ? 1 : 2)
                guard k > 0 else { continue }
                let old = (0 ..< n).map { at($0, y) }
                for x in 0 ..< n { set(x, y, nil, .none) }
                for x in 0 ..< n {
                    let (r, p) = old[x]
                    guard r != nil else { continue }
                    if x < cx { set(x - k, y, r, p) } else if x > cx { set(x + k, y, r, p) } else {
                        // a dark line between the legs must not spread into a dark bar
                        var fill = (r, p)
                        if r == .outline, let side = [old[max(0, x - 1)], old[min(n - 1, x + 1)]].first(where: { $0.0 != nil && $0.0 != .outline }) { fill = side }
                        for d in -k ... k { set(x + d, y, fill.0, fill.1) }
                        set(x, y, r, p)
                    }
                }
            }
            return
        }
        var sagging: [Int] = []
        for x in b.minX ... b.maxX {
            var y = b.minY
            while y <= b.maxY && !solid(x, y) { y += 1 }
            let top = y
            while y <= b.maxY && solid(x, y) { y += 1 }
            let end = y - 1
            if end - top >= 4 && end < b.maxY - 1 && at(x, end).0 == .outline && !solid(x, end + 1) { sagging.append(x) }
        }
        var runs: [[Int]] = []
        for x in sagging { if let last = runs.last?.last, last == x - 1 { runs[runs.count - 1].append(x) } else { runs.append([x]) } }
        for run in runs where run.count >= 3 {
            for (i, x) in run.enumerated() {
                let edge = min(i, run.count - 1 - i)
                let k = edge == 0 ? 1 : (run.count >= 5 ? 2 : 1)
                var y = b.minY
                while !solid(x, y) { y += 1 }
                while solid(x, y + 1) { y += 1 }
                let p = at(x, y - 1).1
                for d in 0 ..< k { set(x, y + d, .shadow, p == .none ? .body : p) }
                set(x, y + k, .outline, .body)
            }
        }
    }

    private var earPieces: [[(x: Int, y: Int)]] {
        let n = PackFrame.n
        var seen = Set<Int>(), result: [[(x: Int, y: Int)]] = []
        for start in 0 ..< n * n where parts[start] == .ear && !seen.contains(start) {
            var piece: [(x: Int, y: Int)] = [], queue = [start]
            seen.insert(start)
            while let i = queue.popLast() {
                let x = i % n, y = i / n
                piece.append((x, y))
                for dy in -1 ... 1 { for dx in -1 ... 1 {
                    let nx = x + dx, ny = y + dy, j = ny * n + nx
                    guard nx >= 0, ny >= 0, nx < n, ny < n, parts[j] == .ear, !seen.contains(j) else { continue }
                    seen.insert(j)
                    queue.append(j)
                } }
            }
            if piece.count >= 2 { result.append(piece) }
        }
        return result
    }

    mutating func shapeEars(_ kind: EarShape) {
        for ear in earPieces {
            let top = ear.map { $0.y }.min()!, minX = ear.map { $0.x }.min()!, maxX = ear.map { $0.x }.max()!
            switch kind {
            case .normal:
                break
            case .folded:
                // the tips fold down: the top two rows go, the head gets a rounded top
                for p in ear where p.y < top + 2 { set(p.x, p.y, nil, .none) }
                var marks: [(Int, Int)] = []
                for y in max(0, top) ... min(PackFrame.n - 1, top + 4) { for x in max(0, minX - 1) ... min(PackFrame.n - 1, maxX + 1) where solid(x, y) {
                    guard let r = role(x, y), [.fur, .shadow, .light, .pink, .earIn].contains(r) else { continue }
                    if !solid(x, y - 1) || !solid(x - 1, y) || !solid(x + 1, y) { marks.append((x, y)) }
                } }
                for (x, y) in marks { set(x, y, .outline, at(x, y).1) }
            case .big:
                // a sphynx's ear: a tall clean triangle on the same base, its tip leaning outward
                let baseY = ear.map { $0.y }.max()!
                let baseL = ear.filter { $0.y == baseY }.map { $0.x }.min()! - 1, baseR = ear.filter { $0.y == baseY }.map { $0.x }.max()! + 1
                let b = box
                let middle = nose?.x ?? (b.minX + b.maxX) / 2
                let outward = view == .side ? 0 : ((baseL + baseR) / 2 < middle ? -1 : 1)
                let tipX = (outward < 0 ? baseL : (outward > 0 ? baseR : (baseL + baseR) / 2)) + outward
                let height = baseY - top + 3
                for p in ear { set(p.x, p.y, nil, .none) }
                for r in 0 ... height {
                    let t = CGFloat(r) / CGFloat(height), y = baseY - height + r
                    let xl = Int((CGFloat(tipX) + CGFloat(baseL - tipX) * t).rounded()), xr = Int((CGFloat(tipX) + CGFloat(baseR - tipX) * t).rounded())
                    for x in min(xl, xr) ... max(xl, xr) {
                        let edge = x == xl || x == xr || r == 0
                        set(x, y, edge ? .outline : (r >= 2 ? .earIn : .fur), .ear)
                    }
                }
            case .tufted:
                // a lynx tuft: a dark wisp straight up from the tip
                if let tip = ear.min(by: { $0.y < $1.y }) {
                    set(tip.x, tip.y - 1, .outline, .ear)
                    set(tip.x + (tip.x < (nose?.x ?? tip.x) ? -1 : 1), tip.y - 2, .outline, .ear)
                }
            }
        }
    }

    /// A fluffy collar: the cheeks stick out a pixel on every other row
    mutating func addRuff() {
        guard let nz = nose else { return }
        for y in nz.y - 1 ... nz.y + 3 where (y - nz.y) % 2 == 0 {
            var sides: [Int] = []
            if view == .front {
                var l = nz.x, r = nz.x
                while solid(l - 1, y) && nz.x - l < 8 { l -= 1 }
                while solid(r + 1, y) && r - nz.x < 8 { r += 1 }
                sides = [l, r]
            } else {
                let b = box
                let facingLeft = CGFloat(nz.x) < CGFloat(b.minX + b.maxX) / 2
                var e = nz.x
                while solid(e + (facingLeft ? -1 : 1), y) && abs(e - nz.x) < 8 { e += facingLeft ? -1 : 1 }
                sides = [e]
            }
            for x in sides {
                let out = x < nz.x ? x - 1 : x + 1
                guard !solid(out, y) else { continue }
                set(x, y, .light, .body)
                set(out, y, .outline, .body)
            }
        }
    }

    /// Hairless: whiskers are outline pixels sticking out sideways beside the face, with nothing above or below
    mutating func removeWhiskers() {
        guard let nz = nose else { return }
        var gone: [(Int, Int)] = []
        for y in max(0, nz.y - 3) ... min(PackFrame.n - 1, nz.y + 3) { for x in 0 ..< PackFrame.n where at(x, y).0 == .outline && abs(x - nz.x) >= 3 {
            if !solid(x, y - 1) && !solid(x, y + 1) && (!solid(x - 1, y) || !solid(x + 1, y)) { gone.append((x, y)) }
        } }
        for (x, y) in gone { set(x, y, nil, .none) }
    }
}
