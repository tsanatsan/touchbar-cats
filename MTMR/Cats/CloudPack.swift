//
//  CloudPack.swift
//  MTMR
//
//  Cloud pictures for the Touch Bar, packed into one file. A pack holds sets of layers (back to front);
//  of each picture only a 30-pixel band is kept, the one with the most going on, since the bar is that thin.
//  The release build packs the cloud art into the app (the art itself never goes into the repository),
//  and "Load your own clouds…" packs whatever folder, zip or pictures you choose.
//

import AppKit
import ImageIO

enum CloudPack {
    static let bandRows = 30 // one picture pixel per point of the bar's 30-point height

    struct Entry {
        var ru: String
        var en: String
        var layers: [Data] // PNG of each layer's band, back to front

        var name: String { return isRussian ? ru : en }
    }

    // MARK: - Reading and writing packs

    static func read(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let sets = plist["sets"] as? [[String: Any]] else { return [] }
        return sets.compactMap { s in
            guard let layers = s["layers"] as? [Data], !layers.isEmpty else { return nil }
            return Entry(ru: s["ru"] as? String ?? "", en: s["en"] as? String ?? "", layers: layers)
        }
    }

    static func write(_ entries: [Entry], to url: URL) throws {
        let plist: [String: Any] = ["version": 1, "sets": entries.map { ["ru": $0.ru, "en": $0.en, "layers": $0.layers] }]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Making a pack from pictures

    /// Every set found in these folders, zips or pictures. A folder of 1.png, 2.png… is one layered set;
    /// any other picture is a set of its own. A names.json next to the sets gives their order and names.
    static func make(from sources: [URL]) -> [Entry] {
        var entries: [Entry] = []
        var counter = 0
        for source in sources {
            var root = source
            var temp: URL?
            if source.pathExtension.lowercased() == "zip" {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clouds-\(UUID().uuidString)")
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", source.path, dir.path]
                try? unzip.run()
                unzip.waitUntilExit()
                root = dir
                temp = dir
            }
            for found in findSets(root) {
                counter += 1
                let fallback = found.name ?? tr("Облака \(counter)", "Clouds \(counter)")
                if let layers = band(found.files) {
                    entries.append(Entry(ru: found.ru ?? fallback, en: found.en ?? fallback, layers: layers))
                }
            }
            if let temp = temp { try? FileManager.default.removeItem(at: temp) }
        }
        return entries
    }

    private struct Found {
        var files: [URL]
        var name: String?
        var ru: String?
        var en: String?
    }

    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]

    private static func findSets(_ root: URL) -> [Found] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return pictureTypes.contains(root.pathExtension.lowercased()) ? [Found(files: [root], name: root.deletingPathExtension().lastPathComponent)] : []
        }
        // names.json: [{"path": "folder", "ru": "…", "en": "…"}] decides what goes in and in which order
        if let data = try? Data(contentsOf: root.appendingPathComponent("names.json")),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            return list.compactMap { item in
                guard let path = item["path"] else { return nil }
                let files = layerFiles(root.appendingPathComponent(path))
                return files.isEmpty ? nil : Found(files: files, ru: item["ru"], en: item["en"])
            }
        }
        var result: [Found] = []
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var dirs = [root]
        while let url = enumerator?.nextObject() as? URL {
            if url.pathComponents.contains("__MACOSX") { continue }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { dirs.append(url) }
        }
        for dir in dirs.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let layered = layerFiles(dir)
            if !layered.isEmpty {
                result.append(Found(files: layered, name: dir.lastPathComponent))
                continue
            }
            let pictures = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { pictureTypes.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for picture in pictures {
                result.append(Found(files: [picture], name: picture.deletingPathExtension().lastPathComponent))
            }
        }
        return result
    }

    /// 1.png, 2.png… in a folder, back to front
    private static func layerFiles(_ dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.deletingPathExtension().lastPathComponent.range(of: "^[0-9]+$", options: .regularExpression) != nil &&
            pictureTypes.contains($0.pathExtension.lowercased()) }
            .sorted { Int($0.deletingPathExtension().lastPathComponent)! < Int($1.deletingPathExtension().lastPathComponent)! }
    }

    // MARK: - The band

    private struct Pixels {
        let w: Int, h: Int
        var data: [UInt8]
    }

    private static func pixels(_ image: CGImage, w: Int, h: Int) -> Pixels {
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // pictures much bigger than pixel art get scaled down smoothly, pixel art stays as is
            ctx.interpolationQuality = (w == image.width && h == image.height) ? .none : .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Pixels(w: w, h: h, data: data)
    }

    /// The layers cut down to the most interesting 30-row band, as PNG data
    private static func band(_ files: [URL]) -> [Data]? {
        let images = files.compactMap { url -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        guard let first = images.first, first.height >= bandRows else { return nil }
        // big pictures come down to about the size of pixel-art backgrounds, where a 30-row band shows real clouds
        let scale = first.height > 420 ? 324 / CGFloat(first.height) : 1
        let w = max(1, Int(CGFloat(first.width) * scale)), h = max(bandRows, Int(CGFloat(first.height) * scale))
        let layers = images.map { pixels($0, w: w, h: h) }

        // the composite picks the band: count the edges between differing pixels in every row
        var composite = [CGFloat](repeating: 0, count: w * h * 3)
        for layer in layers {
            for i in 0 ..< w * h {
                let a = CGFloat(layer.data[i * 4 + 3]) / 255
                guard a > 0 else { continue }
                for c in 0 ..< 3 { composite[i * 3 + c] = composite[i * 3 + c] * (1 - a) + CGFloat(layer.data[i * 4 + c]) }
            }
        }
        // a 3x3 blur first: dithered skies are all edges up close, but not where the clouds really are
        var smooth = composite
        for y in 1 ..< h - 1 {
            for x in 1 ..< w - 1 {
                for c in 0 ..< 3 {
                    var sum: CGFloat = 0
                    for dy in -1 ... 1 { for dx in -1 ... 1 { sum += composite[((y + dy) * w + x + dx) * 3 + c] } }
                    smooth[(y * w + x) * 3 + c] = sum / 9
                }
            }
        }
        composite = smooth
        var rowScore = [CGFloat](repeating: 0, count: h)
        for y in 0 ..< h - 1 {
            var s: CGFloat = 0
            for x in 0 ..< w - 1 {
                let i = (y * w + x) * 3, r = i + 3, d = i + w * 3
                let dx = abs(composite[i] - composite[r]) + abs(composite[i + 1] - composite[r + 1]) + abs(composite[i + 2] - composite[r + 2])
                let dy = abs(composite[i] - composite[d]) + abs(composite[i + 1] - composite[d + 1]) + abs(composite[i + 2] - composite[d + 2])
                if dx > 24 { s += 1 }
                if dy > 24 { s += 1 }
            }
            rowScore[y] = s
        }
        let lo = Int(CGFloat(h) * 0.12), hi = max(lo, h - bandRows - Int(CGFloat(h) * 0.08))
        var best = lo, bestScore: CGFloat = -1
        for y0 in lo ... hi {
            let s = rowScore[y0 ..< y0 + bandRows].reduce(0, +)
            if s > bestScore {
                best = y0
                bestScore = s
            }
        }

        return layers.compactMap { layer in
            var rows = Array(layer.data[(best * w * 4) ..< ((best + bandRows) * w * 4)])
            var bw = w
            if !seamless(rows, w: w) { // a picture that doesn't wrap around gets a mirrored twin, so drifting shows no seam
                var twin = [UInt8](repeating: 0, count: w * 2 * bandRows * 4)
                for y in 0 ..< bandRows {
                    for x in 0 ..< w {
                        for c in 0 ..< 4 {
                            let v = rows[(y * w + x) * 4 + c]
                            twin[(y * w * 2 + x) * 4 + c] = v
                            twin[(y * w * 2 + (w * 2 - 1 - x)) * 4 + c] = v
                        }
                    }
                }
                rows = twin
                bw = w * 2
            }
            return png(rows, w: bw, h: bandRows)
        }
    }

    /// Whether the left edge continues the right one about as smoothly as neighboring columns do
    private static func seamless(_ rows: [UInt8], w: Int) -> Bool {
        var edge = 0, inner = 0
        for y in 0 ..< bandRows {
            for c in 0 ..< 4 {
                edge += abs(Int(rows[(y * w) * 4 + c]) - Int(rows[(y * w + w - 1) * 4 + c]))
                inner += abs(Int(rows[(y * w + w / 2) * 4 + c]) - Int(rows[(y * w + w / 2 + 1) * 4 + c]))
            }
        }
        return edge <= inner * 3 + bandRows * 4 * 6
    }

    private static func png(_ rgba: [UInt8], w: Int, h: Int) -> Data? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    // MARK: - Command line, used by the release build

    /// `MTMR --pack-clouds <folder> <out.pack>`
    static func runFromCommandLine() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--pack-clouds"), args.count > i + 2 else { return }
        let entries = make(from: [URL(fileURLWithPath: args[i + 1])])
        do {
            try write(entries, to: URL(fileURLWithPath: args[i + 2]))
            print("Packed \(entries.count) cloud sets")
            exit(entries.isEmpty ? 1 : 0)
        } catch {
            print("Can't write the cloud pack: \(error)")
            exit(1)
        }
    }
}
