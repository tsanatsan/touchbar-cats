//
//  CatsBarItem.swift
//  MTMR
//
//  Touch Bar item showing the shared CatScene. Redraws at 60 fps while something lively happens
//  (30 on battery), 20 fps while cats just stroll, 10 when everyone rests, and almost never while the Mac sleeps.
//

import AppKit

final class CatsBarItem: NSTouchBarItem, CanSetWidth {
    private let catsView = CatsView()

    override var view: NSView? {
        return catsView
    }

    func setWidth(value: CGFloat) {
        catsView.preferredWidth = value
    }
}

final class CatsView: NSView {
    var preferredWidth: CGFloat = AppSettings.showControlStripState ? 700 : 1004 {
        didSet { widthConstraint.constant = preferredWidth }
    }

    private var widthConstraint: NSLayoutConstraint!
    private let cloudHost = CloudHostView()
    private var timer: Timer?
    private var interval: TimeInterval = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: 30))
        allowedTouchTypes = .direct
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
        widthConstraint.isActive = true
        // the clouds live in their own layer tree, moved by Core Animation, not redrawn by this view
        cloudHost.frame = bounds
        cloudHost.autoresizingMask = [.width, .height]
        cloudHost.layer = CloudScene.shared.root
        cloudHost.wantsLayer = true
        cloudHost.isHidden = true
        addSubview(cloudHost)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    /// The Touch Bar lines items up from its right edge, so a full-width view starts a few points left of the glass,
    /// where nothing is seen (a speech bubble there was cut in half). The view is narrowed by that much.
    private func fitToGlass() {
        guard window != nil else { return }
        let left = convert(NSPoint.zero, to: nil).x
        let width = min(preferredWidth, max(100, widthConstraint.constant + left).rounded())
        if abs(width - widthConstraint.constant) >= 1 { widthConstraint.constant = width }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            timer?.invalidate()
            timer = nil
        } else {
            schedule(1.0 / 60)
        }
    }

    private func schedule(_ newInterval: TimeInterval) {
        guard newInterval != interval || timer == nil else { return }
        interval = newInterval
        timer?.invalidate()
        let timer = Timer(timeInterval: newInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let clouds = CloudScene.shared
        if cloudHost.isHidden == clouds.active { cloudHost.isHidden = !clouds.active }
        if clouds.active {
            clouds.layout(width: bounds.width)
            clouds.tick(CACurrentMediaTime())
            schedule(clouds.interval)
            return
        }
        let scene = CatScene.shared
        fitToGlass()
        if bounds.width > 0 { scene.width = bounds.width }
        scene.advance(to: CACurrentMediaTime())
        if !scene.paused && !scene.systemAsleep { needsDisplay = true }
        CatRecorder.shared.capture(scene)

        let wanted: TimeInterval
        if scene.paused || scene.systemAsleep {
            wanted = 1
        } else {
            switch scene.activity {
            case .calm: wanted = 1.0 / 10
            case .ambient: wanted = 1.0 / 20 // a strolling pixel cat moves half a point per frame: smooth enough
            case .lively: wanted = scene.onBattery ? 1.0 / 30 : 1.0 / 60
            }
        }
        schedule(wanted)
    }

    override func draw(_: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if CloudScene.shared.active { return } // the cloud layers cover the bar
        CatScene.shared.draw(in: ctx)
        if CatRecorder.shared.isRecording { // not part of the GIF
            ctx.setFillColor(red: 1, green: 0.23, blue: 0.19, alpha: 0.9)
            ctx.fillEllipse(in: CGRect(x: bounds.width - 7, y: 2, width: 4, height: 4))
        }
    }

    // MARK: - Touches

    private func key(_ touch: NSTouch) -> Int {
        return (touch.identity as AnyObject).hash
    }

    override func touchesBegan(with event: NSEvent) {
        for touch in event.touches(matching: .began, in: self) {
            if CloudScene.shared.active {
                CloudScene.shared.touchBegan(id: key(touch), x: touch.location(in: self).x)
            } else {
                CatScene.shared.touchBegan(id: key(touch), x: touch.location(in: self).x)
            }
        }
        schedule(1.0 / 60)
    }

    override func touchesMoved(with event: NSEvent) {
        for touch in event.touches(matching: .moved, in: self) {
            if CloudScene.shared.active {
                CloudScene.shared.touchMoved(id: key(touch), x: touch.location(in: self).x)
            } else {
                CatScene.shared.touchMoved(id: key(touch), x: touch.location(in: self).x)
            }
        }
    }

    override func touchesEnded(with event: NSEvent) {
        for touch in event.touches(matching: .ended, in: self) {
            CloudScene.shared.touchEnded(id: key(touch))
            CatScene.shared.touchEnded(id: key(touch))
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        for touch in event.touches(matching: .cancelled, in: self) {
            CloudScene.shared.touchEnded(id: key(touch))
            CatScene.shared.touchEnded(id: key(touch))
        }
    }
}
