//
//  ControlStripSliderItem.swift
//  MTMR
//
//  Volume / brightness control that behaves like the system Control Strip:
//  - touch and slide: the button opens into a slider and follows the finger right away;
//  - tap: the slider stays open, drag the knob or tap the side icons to step;
//  - closes by itself shortly after the last touch.
//

import AppKit

final class ControlStripSliderItem: NSTouchBarItem, CanSetWidth {
    private let control: ControlStripSliderView

    init(identifier: NSTouchBarItem.Identifier, source: LevelSource) {
        control = ControlStripSliderView(source: source)
        super.init(identifier: identifier)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var view: NSView? {
        return control
    }

    func setWidth(value: CGFloat) {
        control.collapsedWidth = value
    }
}

final class ControlStripSliderView: NSView {
    private enum State {
        case collapsed
        case sliding // finger went down on the button and is still dragging
        case expanded // opened by a tap, or released after sliding
    }

    var collapsedWidth: CGFloat = 58 {
        didSet {
            if state == .collapsed { widthConstraint.constant = collapsedWidth }
        }
    }

    private let expandedWidth: CGFloat = 320
    private let height: CGFloat = 30
    private let inset: CGFloat = 10
    private let iconSlot: CGFloat = 22
    private let knobWidth: CGFloat = 30
    private let step: Float = 1.0 / 16 // same step as the keyboard keys

    private let source: LevelSource
    private var state = State.collapsed
    private var widthConstraint: NSLayoutConstraint!
    private var holdTimer: Timer?
    private var collapseTimer: Timer?
    private var touchStartX: CGFloat = 0 // window coordinates: the view itself moves while it grows
    private var touchStartLevel: Float = 0
    private var touchIsStepping = false

    init(source: LevelSource) {
        self.source = source
        super.init(frame: NSRect(x: 0, y: 0, width: collapsedWidth, height: height))
        allowedTouchTypes = .direct
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: collapsedWidth)
        widthConstraint.isActive = true
        source.onExternalChange = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        holdTimer?.invalidate()
        collapseTimer?.invalidate()
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    // MARK: - Geometry

    /// Range of knob centers; computed for the fully open slider so sliding is 1:1 with the finger
    private func knobRange(width: CGFloat) -> ClosedRange<CGFloat> {
        let start = inset + iconSlot + 6 + knobWidth / 2
        let end = width - inset - iconSlot - 6 - knobWidth / 2
        return start ... max(start, end)
    }

    private var isOpen: Bool {
        return bounds.width > collapsedWidth + 1
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        let bezel = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 1, alpha: 0.17).setFill()
        bezel.fill()

        let level = CGFloat(source.level)
        let midY = bounds.midY

        guard isOpen else {
            drawIcon(source.image(for: source.level), center: NSPoint(x: bounds.midX, y: midY))
            return
        }

        drawIcon(source.minImage, center: NSPoint(x: inset + iconSlot / 2, y: midY), alpha: 0.75)
        drawIcon(source.maxImage, center: NSPoint(x: bounds.width - inset - iconSlot / 2, y: midY))

        let range = knobRange(width: bounds.width)
        let knobX = range.lowerBound + (range.upperBound - range.lowerBound) * level

        let track = NSRect(x: range.lowerBound - knobWidth / 2, y: midY - 2,
                           width: range.upperBound - range.lowerBound + knobWidth, height: 4)
        NSColor(calibratedWhite: 1, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

        var filled = track
        filled.size.width = knobX - track.minX
        NSColor.white.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()

        let knob = NSRect(x: knobX - knobWidth / 2, y: 3, width: knobWidth, height: bounds.height - 6)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.5)
        shadow.shadowBlurRadius = 3
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: knob, xRadius: 6, yRadius: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawIcon(_ image: NSImage?, center: NSPoint, alpha: CGFloat = 1) {
        guard let image = image else { return }
        let size = image.size
        let white = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        white.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        collapseTimer?.invalidate()
        touchStartX = touch.location(in: nil).x
        touchStartLevel = source.level
        touchIsStepping = false

        if state == .collapsed {
            // Holding the finger opens the slider even before it moves, like the system button
            holdTimer = schedule(after: 0.18) { [weak self] in self?.beginSliding() }
        } else {
            state = .expanded
            touchInOpenSlider(touch, began: true)
        }
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = event.touches(matching: .moved, in: self).first else { return }
        let dx = touch.location(in: nil).x - touchStartX

        switch state {
        case .collapsed:
            if abs(dx) > 4 {
                beginSliding()
                slide(by: dx)
            }
        case .sliding:
            slide(by: dx)
        case .expanded:
            touchInOpenSlider(touch, began: false)
        }
    }

    override func touchesEnded(with _: NSEvent) {
        holdTimer?.invalidate()
        switch state {
        case .collapsed:
            setState(.expanded) // a quick tap keeps the slider open
            scheduleCollapse(after: 3)
        case .sliding:
            state = .expanded // can still be grabbed again for a moment
            scheduleCollapse(after: 1)
        case .expanded:
            scheduleCollapse(after: 3)
        }
    }

    override func touchesCancelled(with _: NSEvent) {
        holdTimer?.invalidate()
        if state != .collapsed {
            scheduleCollapse(after: 1)
        }
    }

    private func beginSliding() {
        holdTimer?.invalidate()
        guard state == .collapsed else { return }
        setState(.sliding)
    }

    private func slide(by dx: CGFloat) {
        let range = knobRange(width: expandedWidth)
        setLevel(touchStartLevel + Float(dx / (range.upperBound - range.lowerBound)))
    }

    private func touchInOpenSlider(_ touch: NSTouch, began: Bool) {
        let x = touch.location(in: self).x
        if began {
            if x < inset + iconSlot + 4 {
                touchIsStepping = true
                setLevel(source.level - step)
            } else if x > bounds.width - inset - iconSlot - 4 {
                touchIsStepping = true
                setLevel(source.level + step)
            }
        }
        guard !touchIsStepping else { return }
        let range = knobRange(width: bounds.width)
        setLevel(Float((x - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    private func setLevel(_ value: Float) {
        let old = source.level
        let new = min(max(value, 0), 1)
        source.level = new
        if new != old, new == 0 || new == 1 {
            HapticFeedback.instance.tap(type: .weak)
        }
        needsDisplay = true
    }

    // MARK: - Open / close

    private func setState(_ newState: State) {
        state = newState
        let target = newState == .collapsed ? collapsedWidth : expandedWidth
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            widthConstraint.animator().constant = target
            superview?.layoutSubtreeIfNeeded()
        }
        needsDisplay = true
    }

    private func scheduleCollapse(after seconds: TimeInterval) {
        collapseTimer?.invalidate()
        collapseTimer = schedule(after: seconds) { [weak self] in self?.setState(.collapsed) }
    }

    private func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
