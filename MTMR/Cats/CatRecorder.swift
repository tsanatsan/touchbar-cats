//
//  CatRecorder.swift
//  MTMR
//
//  A 5-second GIF of the Touch Bar in a keyboard-like frame, saved to the Desktop.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

final class CatRecorder {
    static let shared = CatRecorder()

    private(set) var isRecording = false
    private var frames: [CGImage] = []
    private var startTime: CFTimeInterval = 0
    private var nextFrame: CFTimeInterval = 0
    private let duration: CFTimeInterval = 5
    private let fps: Double = 12

    func start() {
        guard !isRecording else { return }
        frames = []
        isRecording = true
        startTime = CACurrentMediaTime()
        nextFrame = startTime
    }

    /// Called by the Touch Bar view after each update
    func capture(_ scene: CatScene) {
        guard isRecording else { return }
        let now = CACurrentMediaTime()
        if now >= nextFrame {
            nextFrame += 1 / fps
            if let frame = render(scene) { frames.append(frame) }
        }
        if now - startTime >= duration { finish(scene) }
    }

    private func render(_ scene: CatScene) -> CGImage? {
        let w = Int(scene.width * 2), h = Int(scene.height * 2)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)) // the scene draws top-down, like the Touch Bar view
        ctx.scaleBy(x: 2, y: -2)
        scene.draw(in: ctx)
        return ctx.makeImage()
    }

    private func finish(_ scene: CatScene) {
        isRecording = false
        let captured = frames
        frames = []
        let delay = 1 / fps
        DispatchQueue.global(qos: .utility).async {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let url = desktop.appendingPathComponent("TouchBar Cats \(formatter.string(from: Date())).gif")
            let ok = CatRecorder.writeGIF(captured, delay: delay, to: url)
            DispatchQueue.main.async {
                guard ok else { return }
                scene.say(tr("GIF на рабочем столе", "GIF saved to Desktop"))
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    /// Frames in a dark rounded frame, like the Touch Bar sitting in the keyboard deck
    private static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) -> Bool {
        guard let first = frames.first,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return false }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let pad = 22, w = first.width + pad * 2, h = first.height + pad * 2
        for frame in frames {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 18, cornerHeight: 18, transform: nil))
            ctx.fillPath()
            let strip = CGRect(x: pad, y: pad, width: frame.width, height: frame.height)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: strip, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.clip()
            ctx.interpolationQuality = .none
            ctx.draw(frame, in: strip)
            ctx.restoreGState()
            if let image = ctx.makeImage() {
                CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
        }
        return CGImageDestinationFinalize(dest)
    }
}
