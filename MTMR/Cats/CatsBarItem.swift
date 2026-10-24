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
    private var timer: Timer?
    private var interval: TimeInterval = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: 30))
        allowedTouchTypes = .direct
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
        widthConstraint.isActive = true
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
        let scene = CatScene.shared
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
            CatScene.shared.touchBegan(id: key(touch), x: touch.location(in: self).x)
        }
        schedule(1.0 / 60)
    }

    override func touchesMoved(with event: NSEvent) {
        for touch in event.touches(matching: .moved, in: self) {
            CatScene.shared.touchMoved(id: key(touch), x: touch.location(in: self).x)
        }
    }

    override func touchesEnded(with event: NSEvent) {
        for touch in event.touches(matching: .ended, in: self) {
            CatScene.shared.touchEnded(id: key(touch))
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        for touch in event.touches(matching: .cancelled, in: self) {
            CatScene.shared.touchEnded(id: key(touch))
        }
    }
}
