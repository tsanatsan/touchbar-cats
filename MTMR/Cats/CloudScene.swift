//
//  CloudScene.swift
//  MTMR
//
//  The clouds mode: instead of the cats, drifting pixel clouds. Layers move at their own speed, the far ones
//  slower, so the sky has depth. The drifting is Core Animation's job: it runs at the display's own rate,
//  perfectly smooth, while the app itself does nothing. A one-finger swipe pulls in the next set like
//  a carousel; two and three fingers still change the volume and the brightness.
//

import AppKit

/// Holds the cloud layers on the bar; touches pass through to the cats' view underneath
final class CloudHostView: NSView {
    override func hitTest(_: NSPoint) -> NSView? { return nil }
}

final class CloudScene {
    static let shared = CloudScene()

    private struct Layer {
        let image: CGImage // several copies side by side, so a whole bar's width can slide by one copy
        let width: CGFloat // one copy, in points: one picture pixel per point
        let tiledWidth: CGFloat
        let speed: CGFloat // points per second
    }

    private(set) var sets: [CloudPack.Entry] = []
    private(set) var ownCount = 0 // the last sets are the ones you loaded yourself

    /// Showing on the bar (switched on after the cats have left)
    private(set) var active = false

    /// The layer the bar shows: a set's container, its neighbor while swiping, the edge fades and the name
    let root = CALayer()
    private var containers: [Int: CALayer] = [:]
    private var builtWidth: CGFloat = 0
    private let fades = [CAGradientLayer(), CAGradientLayer()]
    private let pill = CALayer()
    private let text = CATextLayer()

    // the carousel: the current set shifted by `shift`, the neighbor following it
    private var shift: CGFloat = 0
    private var dragStart: (x: CGFloat, shift: CGFloat)?
    private var dragTouch: Int?
    private var lastMoves: [(x: CGFloat, time: CFTimeInterval)] = []
    private var settle: (from: CGFloat, to: CGFloat, start: CFTimeInterval)?
    private var touchCount = 0

    var width: CGFloat = 1004
    let height: CGFloat = 30

    private static let ownURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TouchBar Cats/MyClouds.pack")

    init() {
        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        root.masksToBounds = true
        for (i, fade) in fades.enumerated() {
            fade.colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)]
            fade.startPoint = CGPoint(x: i == 0 ? 0 : 1, y: 0.5)
            fade.endPoint = CGPoint(x: i == 0 ? 1 : 0, y: 0.5)
            fade.zPosition = 10
            root.addSublayer(fade)
        }
        pill.backgroundColor = CGColor(gray: 0, alpha: 0.45)
        pill.zPosition = 20
        pill.opacity = 0
        text.contentsScale = 2
        text.alignmentMode = .center
        text.foregroundColor = CGColor(gray: 1, alpha: 1)
        text.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        text.fontSize = 12
        pill.addSublayer(text)
        root.addSublayer(pill)
        reload()
    }

    func reload() {
        let builtIn = Bundle.main.url(forResource: "Clouds", withExtension: "pack").map(CloudPack.read) ?? []
        let own = CloudPack.read(CloudScene.ownURL)
        sets = builtIn + own
        ownCount = own.count
        if index >= sets.count { index = 0 }
        rebuild()
    }

    var index: Int {
        get { return UserDefaults.standard.integer(forKey: "cats.clouds.index") }
        set { UserDefaults.standard.set(newValue, forKey: "cats.clouds.index") }
    }

    var drifting: Bool {
        get { return UserDefaults.standard.object(forKey: "cats.clouds.drift") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "cats.clouds.drift")
            rebuild()
        }
    }

    // MARK: - Switching on and off

    func show() {
        guard !sets.isEmpty else { return }
        active = true
        place()
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = 0.45
        root.add(fadeIn, forKey: "fadeIn")
        showName()
    }

    func hide() {
        active = false
        rebuild() // the images go, a few megabytes back
    }

    func select(_ i: Int) {
        guard sets.indices.contains(i) else { return }
        index = i
        shift = 0
        settle = nil
        place()
        showName()
    }

    // MARK: - Your own clouds

    func addOwn(_ entries: [CloudPack.Entry]) throws {
        try CloudPack.write(CloudPack.read(CloudScene.ownURL) + entries, to: CloudScene.ownURL)
        let first = sets.count
        reload()
        select(first)
    }

    func removeOwn() {
        try? FileManager.default.removeItem(at: CloudScene.ownURL)
        reload()
        select(min(index, max(0, sets.count - 1)))
    }

    // MARK: - Layers

    private func wrap(_ i: Int) -> Int { return (i % sets.count + sets.count) % sets.count }

    private func rebuild() {
        containers.values.forEach { $0.removeFromSuperlayer() }
        containers = [:]
        builtWidth = 0
    }

    /// Called with the bar's width on every tick: builds what's missing, nothing more
    func layout(width w: CGFloat) {
        guard active, w > 0 else { return }
        if w != builtWidth {
            rebuild()
            builtWidth = w
            width = w
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.frame = CGRect(x: 0, y: 0, width: w, height: height)
            fades[0].frame = CGRect(x: 0, y: 0, width: 10, height: height)
            fades[1].frame = CGRect(x: w - 10, y: 0, width: 10, height: height)
            CATransaction.commit()
            place()
            showName()
        }
    }

    private func layers(_ i: Int) -> [Layer] {
        let entry = sets[i]
        let count = entry.layers.count
        return entry.layers.enumerated().compactMap { n, data in
            guard let src = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let w = image.width, h = image.height
            let copies = Int(ceil(width / CGFloat(w))) + 1
            // twice the size in device pixels, nearest-neighbor, in the bar's own color space
            let opaque = n == 0
            guard let ctx = CGContext(data: nil, width: w * 2 * copies, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0, space: displaySpace,
                                      bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue) else { return nil }
            ctx.interpolationQuality = .none
            for c in 0 ..< copies { ctx.draw(image, in: CGRect(x: c * w * 2, y: 0, width: w * 2, height: h * 2)) }
            guard let tiled = ctx.makeImage() else { return nil }
            // the back layer stays, the nearer a layer the faster it drifts
            let speed: CGFloat = count > 1 ? (n == 0 ? 0 : CGFloat(n) / CGFloat(count - 1) * 3.2) : 1.2
            return Layer(image: tiled, width: CGFloat(w), tiledWidth: CGFloat(w * copies), speed: speed)
        }
    }

    private func container(_ i: Int) -> CALayer {
        let i = wrap(i)
        if let c = containers[i] { return c }
        if containers.count > 3 {
            for (k, c) in containers where k != wrap(index) && k != wrap(index + 1) && k != wrap(index - 1) {
                c.removeFromSuperlayer()
                containers[k] = nil
            }
        }
        let c = CALayer()
        c.anchorPoint = .zero
        c.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        c.masksToBounds = true
        for layer in layers(i) {
            let l = CALayer()
            l.anchorPoint = .zero
            l.frame = CGRect(x: 0, y: 0, width: layer.tiledWidth, height: height)
            l.contents = layer.image
            l.contentsScale = 2
            // a drifting layer is sampled smoothly, so it glides between pixels instead of stepping a pixel at a time
            l.magnificationFilter = layer.speed > 0 && drifting ? .linear : .nearest
            l.minificationFilter = layer.speed > 0 && drifting ? .linear : .nearest
            l.isOpaque = layer.speed == 0
            if drifting && layer.speed > 0 {
                let drift = CABasicAnimation(keyPath: "position.x")
                drift.fromValue = 0
                drift.toValue = -layer.width
                drift.duration = CFTimeInterval(layer.width / layer.speed)
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .linear)
                drift.isRemovedOnCompletion = false
                l.add(drift, forKey: "drift")
            }
            c.addSublayer(l)
        }
        root.addSublayer(c)
        containers[i] = c
        return c
    }

    /// Puts the current set (and the neighbor while swiping) where `shift` says, without implicit animations
    private func place() {
        guard active, !sets.isEmpty, builtWidth > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let current = wrap(index)
        var shown: Set<Int> = [current]
        container(current).position = CGPoint(x: shift, y: 0)
        if sets.count > 1 && shift != 0 {
            let neighbor = wrap(index + (shift < 0 ? 1 : -1))
            container(neighbor).position = CGPoint(x: shift < 0 ? shift + width : shift - width, y: 0)
            shown.insert(neighbor)
        }
        for (k, c) in containers { c.isHidden = !shown.contains(k) }
        CATransaction.commit()
    }

    /// The set's name for a moment after switching, in a soft dark pill
    private func showName() {
        guard sets.indices.contains(index), builtWidth > 0 else { return }
        let string = NSAttributedString(string: sets[index].name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        let size = string.size()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        text.string = sets[index].name
        pill.frame = CGRect(x: (width - size.width) / 2 - 10, y: (height - size.height - 4) / 2, width: size.width + 20, height: size.height + 4)
        pill.cornerRadius = pill.frame.height / 2
        text.frame = CGRect(x: 0, y: 1, width: pill.frame.width, height: size.height + 2)
        CATransaction.commit()
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 1, 1, 0]
        blink.keyTimes = [0, 0.1, 0.7, 1]
        blink.duration = 1.7
        pill.add(blink, forKey: "name")
    }

    // MARK: - Time

    /// Only the swipe needs the app's own timer; the drifting runs by itself
    func tick(_ now: CFTimeInterval) {
        guard active, let s = settle else { return }
        let k = min(1, CGFloat(now - s.start) / 0.32)
        shift = s.from + (s.to - s.from) * (1 - pow(1 - k, 3))
        if k >= 1 {
            settle = nil
            if s.to != 0 { // the neighbor has arrived: it's the current set now
                index = wrap(index + (s.to < 0 ? 1 : -1))
                shift = 0
                showName()
            }
        }
        place()
    }

    var interval: TimeInterval {
        return active && (settle != nil || dragTouch != nil) ? 1.0 / 60 : 1
    }

    // MARK: - Swipes

    func touchBegan(id: Int, x: CGFloat) {
        touchCount += 1
        guard touchCount == 1, sets.count > 1 else {
            cancelDrag() // two or three fingers: that's volume or brightness, not a swipe
            return
        }
        dragTouch = id
        settle = nil
        dragStart = (x, shift)
        lastMoves = [(x, CACurrentMediaTime())]
    }

    func touchMoved(id: Int, x: CGFloat) {
        guard id == dragTouch, let start = dragStart, touchCount == 1 else { return }
        shift = max(-width, min(width, start.shift + x - start.x))
        lastMoves.append((x, CACurrentMediaTime()))
        if lastMoves.count > 6 { lastMoves.removeFirst() }
        place()
    }

    func touchEnded(id: Int) {
        touchCount = max(0, touchCount - 1)
        guard id == dragTouch else { return }
        dragTouch = nil
        dragStart = nil
        var v: CGFloat = 0
        if let a = lastMoves.first, let b = lastMoves.last, b.time - a.time > 0.01, CACurrentMediaTime() - b.time < 0.1 {
            v = (b.x - a.x) / CGFloat(b.time - a.time)
        }
        // far enough or fast enough: the neighbor slides in; otherwise everything springs back
        let to: CGFloat
        if shift < -width * 0.18 || (v < -300 && shift < -8) {
            to = -width
        } else if shift > width * 0.18 || (v > 300 && shift > 8) {
            to = width
        } else {
            to = 0
        }
        if to != 0 { HapticFeedback.instance.tap(type: .weak) }
        settle = (shift, to, CACurrentMediaTime())
    }

    private func cancelDrag() {
        guard dragTouch != nil || shift != 0 else { return }
        dragTouch = nil
        dragStart = nil
        settle = (shift, 0, CACurrentMediaTime())
    }
}
