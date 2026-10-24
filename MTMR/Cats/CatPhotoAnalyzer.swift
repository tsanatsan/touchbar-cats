//
//  CatPhotoAnalyzer.swift
//  MTMR
//
//  Turns a photo of a real cat into pixel-cat parameters, on device with Apple Vision:
//  find the cat, cut it out of the background, find eyes and nose, cluster the fur
//  colors and guess the coat pattern. The photo itself is never stored.
//

import AppKit
import Vision

struct PhotoAnalysis {
    var record: CustomCat
    var foundCat: Bool
}

private struct Sample {
    var r: Float
    var g: Float
    var b: Float

    var luminance: Float { return 0.299 * r + 0.587 * g + 0.114 * b }
    var saturation: Float {
        let mx = max(r, g, b), mn = min(r, g, b)
        return mx > 0 ? (mx - mn) / mx : 0
    }

    /// Hue in degrees, 0...360
    var hue: Float {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0.0001 else { return 0 }
        var h: Float
        if mx == r { h = (g - b) / d } else if mx == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    func distance(_ o: Sample) -> Float {
        let dr = r - o.r, dg = g - o.g, db = b - o.b
        return dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11
    }

    var hex: UInt32 {
        func c(_ v: Float) -> UInt32 { return UInt32(max(0, min(255, (v * 255).rounded()))) }
        return c(r) << 16 | c(g) << 8 | c(b)
    }
}

private struct Cluster {
    var color: Sample
    var share: Float
}

enum CatPhotoAnalyzer {
    static func analyze(_ image: NSImage) -> PhotoAnalysis? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // work on a small copy: faster, and fur colors don't need detail
        let scale = min(1, 512 / CGFloat(max(source.width, source.height)))
        let w = max(1, Int(CGFloat(source.width) * scale)), h = max(1, Int(CGFloat(source.height) * scale))
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return nil }

        func pixel(_ x: Int, _ y: Int) -> Sample { // y from the top
            let i = (y * w + x) * 4
            return Sample(r: Float(rgba[i]) / 255, g: Float(rgba[i + 1]) / 255, b: Float(rgba[i + 2]) / 255)
        }

        // 1. where is the cat
        let animals = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: small, options: [:])
        try? handler.perform([animals])
        let observations = (animals.results ?? []).sorted { a, b in
            let ca = a.labels.contains { $0.identifier == VNAnimalIdentifier.cat.rawValue }
            let cb = b.labels.contains { $0.identifier == VNAnimalIdentifier.cat.rawValue }
            return ca != cb ? ca : a.confidence > b.confidence
        }
        let box = observations.first?.boundingBox // normalized, origin bottom-left
        let rect = box.map { CGRect(x: $0.minX * CGFloat(w), y: (1 - $0.maxY) * CGFloat(h), width: $0.width * CGFloat(w), height: $0.height * CGFloat(h)) }
            ?? CGRect(x: CGFloat(w) * 0.15, y: CGFloat(h) * 0.15, width: CGFloat(w) * 0.7, height: CGFloat(h) * 0.7)

        // 2. which pixels are cat: Vision's subject mask, or an oval inside the box
        var mask = [Bool](repeating: false, count: w * h)
        var masked = false
        if #available(macOS 14.0, *) { masked = subjectMask(small, rect: rect, w: w, h: h, into: &mask) }
        if !masked {
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let nx = (CGFloat(x) - rect.midX) / (rect.width * 0.42), ny = (CGFloat(y) - rect.midY) / (rect.height * 0.42)
                    mask[y * w + x] = nx * nx + ny * ny <= 1
                }
            }
        }

        // 3. eyes and nose
        var eyePoints: [CGPoint] = [], nosePoint: CGPoint?
        if #available(macOS 14.0, *) { (eyePoints, nosePoint) = facePoints(small, w: w, h: h) }

        // 4. fur colors
        var samples: [Sample] = []
        let step = max(1, Int(sqrt(Double(mask.filter { $0 }.count) / 5000)))
        for y in Swift.stride(from: 0, to: h, by: step) {
            for x in Swift.stride(from: 0, to: w, by: step) where mask[y * w + x] {
                samples.append(pixel(x, y))
            }
        }
        guard samples.count > 30 else { return nil }
        let clusters = kMeans(samples, k: 4)

        func region(_ p: CGPoint, _ radius: CGFloat) -> [Sample] {
            var out: [Sample] = []
            let r = Int(max(2, radius))
            for dy in -r ... r {
                for dx in -r ... r where dx * dx + dy * dy <= r * r {
                    let x = Int(p.x) + dx, y = Int(p.y) + dy
                    if x >= 0, y >= 0, x < w, y < h { out.append(pixel(x, y)) }
                }
            }
            return out
        }
        let unit = rect.width

        // 5. the main fur color is what the forehead looks like, not simply the most common one:
        // a white chest or dark stripes often take more pixels than the fur itself
        var bounds = (minX: w, minY: h, maxX: 0, maxY: 0)
        for y in 0 ..< h {
            for x in 0 ..< w where mask[y * w + x] {
                bounds = (min(bounds.minX, x), min(bounds.minY, y), max(bounds.maxX, x), max(bounds.maxY, y))
            }
        }
        let catWidth = CGFloat(max(1, bounds.maxX - bounds.minX))
        var foreheadSamples: [Sample] = []
        if eyePoints.count == 2 {
            let mid = CGPoint(x: (eyePoints[0].x + eyePoints[1].x) / 2, y: (eyePoints[0].y + eyePoints[1].y) / 2)
            let d = hypot(eyePoints[0].x - eyePoints[1].x, eyePoints[0].y - eyePoints[1].y)
            foreheadSamples = region(CGPoint(x: mid.x, y: mid.y - d * 0.6), d * 0.35)
        }
        if foreheadSamples.count < 10 { // top middle of the cat
            let top = bounds.minY + (bounds.maxY - bounds.minY) / 6
            foreheadSamples = region(CGPoint(x: CGFloat(bounds.minX + bounds.maxX) / 2, y: CGFloat(top)), catWidth * 0.12)
        }
        let forehead = median(foreheadSamples)
        func nearest(_ c: Sample) -> Cluster { return clusters.min { c.distance($0.color) < c.distance($1.color) }! }

        let whiteFamily = clusters.filter { $0.color.luminance > 0.5 && $0.color.saturation < 0.26 } // white fur in shade too
        let white = clusters.filter { $0.color.luminance > 0.74 && $0.color.saturation < 0.2 }
        let black = clusters.filter { $0.color.luminance < 0.27 && $0.color.saturation < 0.35 }
        let orange = clusters.filter { c in
            let h = c.color.hue
            return h >= 12 && h <= 48 && c.color.saturation > 0.18 && c.color.luminance > 0.22 && c.color.luminance < 0.85
        }
        let share = { (list: [Cluster]) in list.reduce(Float(0)) { $0 + $1.share } }
        let whiteShare = share(white), blackShare = share(black), orangeShare = share(orange)
        let lightest = clusters.max { $0.color.luminance < $1.color.luminance }!

        let foreheadFound = eyePoints.count == 2 && foreheadSamples.count >= 10
        var fur = foreheadFound ? forehead : nearest(forehead).color
        // a white cat: mostly pale, and its lightest color has almost no tint (light ginger fur is warm)
        let isWhiteCat = share(whiteFamily) > 0.6 && lightest.color.luminance > 0.82 && lightest.color.saturation < 0.12 && blackShare < 0.08
        if isWhiteCat { fur = lightest.color }
        let darker = clusters.filter { $0.color.luminance < fur.luminance - 0.12 }.max { $0.share < $1.share }
        var dark = darker?.color ?? mix(fur, Sample(r: 0, g: 0, b: 0), 0.4)
        var belly = lightest.color.luminance > fur.luminance + 0.12 ? lightest.color : mix(fur, Sample(r: 1, g: 1, b: 1), 0.45)
        var patch: Sample?
        var coat = Coat.solid
        let faceColor = nosePoint.map { median(region($0, unit * 0.07)) }
        let stripes = darker.map { stripeScore(mask, w: w, h: h, pixel: pixel, fur: fur, dark: $0.color) } ?? 0

        if !isWhiteCat && whiteShare > 0.12 && orangeShare > 0.1 && blackShare > 0.07, let o = orange.max(by: { $0.share < $1.share }), let k = black.first {
            coat = .calico // white with orange and black patches
            fur = white.first?.color ?? lightest.color
            dark = o.color
            patch = k.color
            belly = mix(fur, Sample(r: 1, g: 1, b: 1), 0.5)
        } else if let face = faceColor, fur.luminance > 0.55, face.luminance < fur.luminance - 0.25 {
            coat = .points
            dark = face
        } else if !isWhiteCat && !(fur.luminance > 0.74 && fur.saturation < 0.2), let d = darker, d.share > 0.06, d.share < 0.6, stripes > 0.16 {
            coat = .tabby
        } else if whiteShare > 0.4 && blackShare > 0.08 && orangeShare < 0.1, let k = black.first {
            coat = .calico // mostly white with black patches
            fur = white.first?.color ?? lightest.color
            dark = k.color
            patch = k.color
            belly = mix(fur, Sample(r: 1, g: 1, b: 1), 0.5)
        } else if !isWhiteCat && whiteShare > 0.12 {
            coat = fur.luminance < 0.25 ? .tuxedo : .bicolor
            belly = white.first?.color ?? belly
        }
        if !isWhiteCat && coat != .calico {
            fur = vivid(fur, 1.2)
            dark = vivid(dark, 1.15)
        }

        // 6. eyes: from the pose, or the bright colored spots in the upper part of the cat
        let fallbackEye = Sample(r: 0.88, g: 0.69, b: 0.25)
        func eyeColor(_ samples: [Sample]) -> Sample? {
            let usable = samples.filter { $0.luminance > 0.12 && $0.luminance < 0.95 && $0.saturation > 0.15 }
            guard usable.count > 4 else { return nil }
            let top = usable.sorted { $0.saturation > $1.saturation }.prefix(max(3, usable.count / 3))
            return vividEye(median(Array(top)))
        }
        var eyes: [Sample] = []
        if eyePoints.count == 2 {
            eyes = eyePoints.sorted { $0.x < $1.x }.compactMap { eyeColor(region($0, unit * 0.035)) }
        }
        if eyes.count < 2 {
            var left: [Sample] = [], right: [Sample] = []
            let midX = (bounds.minX + bounds.maxX) / 2, lowest = bounds.minY + (bounds.maxY - bounds.minY) * 2 / 3
            for y in bounds.minY ..< max(bounds.minY + 1, lowest) {
                for x in bounds.minX ... bounds.maxX where mask[y * w + x] {
                    let p = pixel(x, y)
                    let plain = clusters.contains { p.distance($0.color) < 0.012 }
                    if p.saturation > 0.35 && p.luminance > 0.2 && p.luminance < 0.92 && !plain {
                        if x < midX { left.append(p) } else { right.append(p) }
                    }
                }
            }
            if left.count > 15 && right.count > 15 { eyes = [left, right].compactMap(eyeColor) }
        }
        let eye = eyes.first ?? fallbackEye
        let eye2 = eyes.count == 2 && eyes[0].distance(eyes[1]) > 0.04 ? eyes[1] : nil // odd-eyed cats

        var pink = Sample(r: 1, g: 0.6, b: 0.66)
        if let face = faceColor, face.r > face.g + 0.08, face.r > face.b, face.luminance > 0.35 {
            pink = mix(face, Sample(r: 1, g: 0.6, b: 0.66), 0.4)
        } else if let face = faceColor, face.luminance < 0.3 {
            pink = Sample(r: 0.8, g: 0.52, b: 0.56)
        }

        var colors: [String: UInt32] = ["fur": fur.hex, "dark": dark.hex, "belly": belly.hex, "eye": eye.hex, "pink": pink.hex]
        if let eye2 = eye2 { colors["eye2"] = eye2.hex }
        if let patch = patch { colors["patch"] = patch.hex }
        let record = CustomCat(id: "custom-" + UUID().uuidString, name: tr("Мой кот", "My cat"), coat: coat.rawValue,
                               ears: EarShape.normal.rawValue, tail: TailShape.normal.rawValue, eyes: EyeShape.round.rawValue,
                               fat: false, ruff: false, colors: colors)
        return PhotoAnalysis(record: record, foundCat: box != nil)
    }

    // MARK: - Vision helpers

    @available(macOS 14.0, *)
    private static func subjectMask(_ image: CGImage, rect: CGRect, w: Int, h: Int, into mask: inout [Bool]) -> Bool {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let result = request.results?.first else { return false }
        var best: (count: Int, buffer: [Bool])?
        for instance in result.allInstances {
            guard let buffer = try? result.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { continue }
            let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            var m = [Bool](repeating: false, count: w * h)
            var inside = 0
            for y in 0 ..< h {
                let by = min(bh - 1, y * bh / h)
                let row = base.advanced(by: by * rowBytes).assumingMemoryBound(to: Float32.self)
                for x in 0 ..< w where row[min(bw - 1, x * bw / w)] > 0.5 {
                    m[y * w + x] = true
                    if rect.contains(CGPoint(x: x, y: y)) { inside += 1 }
                }
            }
            if inside > (best?.count ?? 0) { best = (inside, m) }
        }
        guard let chosen = best, chosen.count > 50 else { return false }
        mask = chosen.buffer
        return true
    }

    @available(macOS 14.0, *)
    private static func facePoints(_ image: CGImage, w: Int, h: Int) -> ([CGPoint], CGPoint?) {
        let request = VNDetectAnimalBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let pose = request.results?.first else { return ([], nil) }
        func point(_ joint: VNAnimalBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? pose.recognizedPoint(joint), p.confidence > 0.3 else { return nil }
            return CGPoint(x: p.location.x * CGFloat(w), y: (1 - p.location.y) * CGFloat(h))
        }
        return ([point(.leftEye), point(.rightEye)].compactMap { $0 }, point(.nose))
    }

    // MARK: - Color math

    private static func kMeans(_ samples: [Sample], k: Int) -> [Cluster] {
        // deterministic k-means++ style start: spread the centers far apart
        var centers = [samples[samples.count / 2]]
        while centers.count < k {
            let far = samples.max { a, b in
                centers.map { a.distance($0) }.min()! < centers.map { b.distance($0) }.min()!
            }!
            centers.append(far)
        }
        var labels = [Int](repeating: 0, count: samples.count)
        for _ in 0 ..< 12 {
            for (i, s) in samples.enumerated() {
                labels[i] = centers.indices.min { s.distance(centers[$0]) < s.distance(centers[$1]) }!
            }
            for c in centers.indices {
                let members = samples.indices.filter { labels[$0] == c }.map { samples[$0] }
                if members.isEmpty { continue }
                centers[c] = median(members)
            }
        }
        return centers.indices.map { c in
            Cluster(color: centers[c], share: Float(labels.filter { $0 == c }.count) / Float(samples.count))
        }.filter { $0.share > 0.03 }.sorted { $0.share > $1.share }
    }

    private static func median(_ samples: [Sample]) -> Sample {
        guard !samples.isEmpty else { return Sample(r: 0.5, g: 0.5, b: 0.5) }
        func m(_ v: [Float]) -> Float { return v.sorted()[v.count / 2] }
        return Sample(r: m(samples.map { $0.r }), g: m(samples.map { $0.g }), b: m(samples.map { $0.b }))
    }

    private static func mix(_ a: Sample, _ b: Sample, _ k: Float) -> Sample {
        return Sample(r: a.r + (b.r - a.r) * k, g: a.g + (b.g - a.g) * k, b: a.b + (b.b - a.b) * k)
    }

    /// Share of neighbouring cat pixels that switch between the fur and the darker color: high for stripes
    private static func stripeScore(_ mask: [Bool], w: Int, h: Int, pixel: (Int, Int) -> Sample, fur: Sample, dark: Sample) -> Float {
        var switches = 0, pairs = 0
        for y in Swift.stride(from: 0, to: h, by: 2) {
            var last: Bool?
            for x in 0 ..< w where mask[y * w + x] {
                let p = pixel(x, y)
                let isDark = p.distance(dark) < p.distance(fur)
                if let l = last {
                    pairs += 1
                    if l != isDark { switches += 1 }
                }
                last = isDark
            }
        }
        return pairs > 0 ? Float(switches) / Float(pairs) * 4 : 0 // scaled: stripes switch every few pixels
    }

    /// Photos look washed out next to pixel art: push the saturation a little
    private static func vivid(_ c: Sample, _ k: Float) -> Sample {
        let l = c.luminance
        func ch(_ x: Float) -> Float { return max(0, min(1, l + (x - l) * k)) }
        return Sample(r: ch(c.r), g: ch(c.g), b: ch(c.b))
    }

    private static func vividEye(_ c: Sample) -> Sample {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        guard mx > 0.01 else { return Sample(r: 0.88, g: 0.69, b: 0.25) }
        let s = max((mx - mn) / mx, 0.55), v = max(mx, 0.7)
        func ch(_ x: Float) -> Float { return v - (v - (x - mn) / max(0.001, mx - mn) * v) * s }
        return Sample(r: ch(c.r), g: ch(c.g), b: ch(c.b))
    }
}
