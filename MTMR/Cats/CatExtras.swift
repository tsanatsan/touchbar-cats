//
//  CatExtras.swift
//  MTMR
//
//  Everything around the cats: toys (mouse, laser, box, bowl), whole-word commands, kittens,
//  seasons and holidays, battery, a pomodoro timer and typing stats.
//

import AppKit
import CoreAudio
import IOKit.ps

final class CatMouse {
    var x: CGFloat
    var dir: CGFloat
    var pause: CGFloat = 0
    var frame: CGFloat = 0
    var scared: CGFloat = 0
    weak var hunter: Cat?

    init(x: CGFloat, dir: CGFloat) {
        self.x = x
        self.dir = dir
    }
}

final class CatBox {
    var x: CGFloat
    var life: CGFloat = 90
    var rest: CGFloat = 1.5
    weak var occupant: Cat?

    init(x: CGFloat) { self.x = x }
}

final class CatBowl {
    var x: CGFloat
    var life: CGFloat = 12

    init(x: CGFloat) { self.x = x }
}

/// The red dot follows a finger on the trackpad, right above it on the bar
struct LaserDot {
    var active = false
    var x: CGFloat = 0
    var y: CGFloat = 0
    var touchStart: (x: CGFloat, y: CGFloat)?
    var lastMove: CGFloat = 0
}

struct Flake {
    enum Kind { case snow, leaf, petal, butterfly, bat }
    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var phase: CGFloat
    var color: RGB
}

struct CatCalendar {
    enum Season { case winter, spring, summer, autumn }
    var season: Season
    var newYear: Bool
    var halloween: Bool
    var valentine: Bool

    static func now() -> CatCalendar {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        let m = c.month ?? 1, d = c.day ?? 1
        let season: Season = [12, 1, 2].contains(m) ? .winter : (m <= 5 ? .spring : (m <= 8 ? .summer : .autumn))
        return CatCalendar(season: season,
                           newYear: (m == 12 && d >= 20) || (m == 1 && d <= 10),
                           halloween: (m == 10 && d >= 24) || (m == 11 && d == 1),
                           valentine: m == 2 && d >= 12 && d <= 14)
    }
}

final class TypingStats {
    private(set) var typed = 0
    private(set) var bestCaught = 0
    private(set) var totalCaught = 0
    private(set) var bestSpeed = 0
    private var day = ""
    private var recent: [CFTimeInterval] = []

    init() {
        let d = UserDefaults.standard
        day = d.string(forKey: "cats.stats.day") ?? ""
        typed = day == TypingStats.today() ? d.integer(forKey: "cats.stats.typed") : 0
        bestCaught = d.integer(forKey: "cats.stats.bestCaught")
        totalCaught = d.integer(forKey: "cats.stats.totalCaught")
        bestSpeed = d.integer(forKey: "cats.stats.bestSpeed")
    }

    /// Characters in the last minute
    var speed: Int {
        let now = CACurrentMediaTime()
        return recent.filter { now - $0 <= 60 }.count
    }

    func keyTyped() {
        rollDay()
        typed += 1
        let now = CACurrentMediaTime()
        recent.append(now)
        recent.removeAll { now - $0 > 60 }
        // a record needs a full minute of typing to count
        if let first = recent.first, now - first > 50 { bestSpeed = max(bestSpeed, recent.count) }
    }

    func caught(today: Int) {
        rollDay()
        totalCaught += 1
        bestCaught = max(bestCaught, today)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(day, forKey: "cats.stats.day")
        d.set(typed, forKey: "cats.stats.typed")
        d.set(bestCaught, forKey: "cats.stats.bestCaught")
        d.set(totalCaught, forKey: "cats.stats.totalCaught")
        d.set(bestSpeed, forKey: "cats.stats.bestSpeed")
    }

    private func rollDay() {
        let today = TypingStats.today()
        if day != today {
            day = today
            typed = 0
        }
    }

    private static func today() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

final class CatExtras {
    var mouse: CatMouse?
    var nextMouseAt: CGFloat = .random(in: 240 ... 480)
    var box: CatBox?
    var nextBoxAt: CGFloat = .random(in: 900 ... 1800)
    var bowl: CatBowl?
    var laser = LaserDot()
    var flakes: [Flake] = []
    var flakeT: CGFloat = 0
    var calendar = CatCalendar.now()
    var calendarCheckAt: CGFloat = 0

    var word = ""
    var wordX: CGFloat = 0
    var wordTime: CGFloat = 0
    var wordDone = false // already recognized during a pause, the separator must not repeat it
    var previousWord = ""

    var batteryLevel: CGFloat = 1
    var pluggedIn = false
    var batteryCheckAt: CGFloat = 2
    var lowBattery: Bool { return batteryLevel < 0.2 && !pluggedIn }

    var pomodoroEnd: Date?
    weak var pomodoroCat: Cat?

    let stats = TypingStats()
}

private func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { return .random(in: a ... b) }
private func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { return max(a, min(b, v)) }

extension CatScene {
    // MARK: - Words typed as a whole

    func appendWord(_ ch: String, x: CGFloat) {
        extras.word = String((extras.word + ch).suffix(24))
        extras.wordX = x
        extras.wordTime = t
    }

    func wordBackspace() {
        if !extras.word.isEmpty { extras.word.removeLast() }
    }

    func noteTyped() {
        extras.stats.keyTyped()
    }

    func endWord(x: CGFloat) {
        let w = extras.word
        let done = extras.wordDone
        extras.word = ""
        extras.wordDone = false
        guard !w.isEmpty else { return }
        defer { extras.previousWord = w }
        if !done { runWord(w) }
    }

    /// A word also counts when typing pauses right after it, no space needed
    private func checkWordPause() {
        guard !extras.word.isEmpty, !extras.wordDone, t - extras.wordTime > 0.7 else { return }
        extras.wordDone = runWord(extras.word)
    }

    @discardableResult
    private func runWord(_ w: String) -> Bool {
        let at = extras.wordX
        if ["кот", "cat"].contains(extras.previousWord), let minutes = Int(w) {
            startPomodoro(minutes: minutes, x: at)
            return true
        }
        let action: (() -> Void)?
        switch w {
        case "рыба", "рыбка", "еда", "кушать", "fish", "food": action = { self.putBowl(at: at) }
        case "спать", "sleep": action = { self.everyoneSleeps() }
        case "привет", "hello": action = { self.everyoneWaves(at: at) }
        case "фу", "bad": action = { self.everyoneSulks(at: at) }
        case "коробка", "box": action = { self.putBox(at: at) }
        case "мышка", "мышь", "mouse": action = { self.releaseMouse(towards: at) }
        default:
            action = cats.first(where: { $0.mode != .exit && !$0.removing &&
                ($0.breed.name.lowercased() == w || $0.breed.displayName.lowercased() == w) }).map { cat in { self.callByName(cat, at: at) } }
        }
        guard let run = action else { return false }
        dissolveWord(w.count)
        run()
        return true
    }

    private func idleCats(_ near: CGFloat? = nil, within: CGFloat = 10_000) -> [Cat] {
        let calm: [CatMode] = [.sit, .walk, .groom, .run, .boop, .loaf, .yawn, .stretch, .munch]
        return cats.filter { cat in
            !cat.removing && calm.contains(cat.mode) && (near.map { abs(cat.x - $0) < within } ?? true)
        }
    }

    private func putBowl(at x: CGFloat) {
        let bowl = CatBowl(x: clamp(x, 12, width - 12))
        extras.bowl = bowl
        for (i, cat) in idleCats().enumerated() {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            cat.extraT = side * CGFloat(9 + (i / 2) * 9) // place around the bowl
            if cat.mode == .loaf { spawn(.bang, cat.x + cat.dir * 6, 9) }
            cat.setMode(.eatGo, 99)
        }
    }

    private func everyoneSleeps() {
        for (i, cat) in idleCats().enumerated() {
            pending.append((t + CGFloat(i) * 0.35, { [weak cat] in
                guard let cat = cat, !cat.isExtraMode else { return }
                cat.setMode(.loaf, rnd(25, 50))
            }))
        }
    }

    private func everyoneWaves(at x: CGFloat) {
        for cat in idleCats(x, within: 400) where cat.mode != .loaf {
            cat.dir = x >= cat.x ? 1 : -1
            cat.setMode(.wave, 1.6)
        }
    }

    private func everyoneSulks(at x: CGFloat) {
        for cat in idleCats(x, within: 220) where cat.mode != .loaf {
            cat.dir = x >= cat.x ? -1 : 1 // turn away
            cat.setMode(.sulk, 4)
        }
    }

    private func putBox(at x: CGFloat) {
        extras.box = CatBox(x: clamp(x, 16, width - 16))
    }

    private func releaseMouse(towards x: CGFloat) {
        let fromLeft = x > width / 2
        extras.mouse = CatMouse(x: fromLeft ? -8 : width + 8, dir: fromLeft ? 1 : -1)
    }

    private func callByName(_ cat: Cat, at x: CGFloat) {
        guard !cat.isExtraMode || cat.mode == .sulk || cat.mode == .wave else { return }
        if cat.mode == .loaf { spawn(.bang, cat.x + cat.dir * 6, 9) }
        cat.tx = clamp(x, 14, width - 14)
        cat.setMode(.come, 99)
        pending.append((t + 0.4, { [weak self, weak cat] in
            guard let self = self, let cat = cat else { return }
            self.bubbles.append(Bubble(cat: cat, text: tr("мяу?", "meow?")))
            CatSounds.shared.play(.meow, pan: self.pan(cat.x))
        }))
    }

    private func startPomodoro(minutes: Int, x: CGFloat) {
        if minutes <= 0 {
            if let cat = extras.pomodoroCat { cat.setMode(.stretch, 1) }
            extras.pomodoroEnd = nil
            return
        }
        let m = min(minutes, 180)
        guard let cat = idleCats().min(by: { abs($0.x - x) < abs($1.x - x) }) else { return }
        extras.pomodoroCat?.setMode(.stretch, 1)
        extras.pomodoroEnd = Date().addingTimeInterval(TimeInterval(m * 60))
        extras.pomodoroCat = cat
        cat.setMode(.pomodoro, 99)
        bubbles.append(Bubble(cat: cat, text: tr("\(m) мин", "\(m) min"), life: 2.5))
    }

    /// Stereo position for a sound: -1 left ... 1 right
    func pan(_ x: CGFloat) -> CGFloat {
        return clamp(x / max(1, width) * 2 - 1, -1, 1)
    }

    func say(_ text: String) {
        if let cat = cats.filter({ $0.x > 20 && $0.x < width - 20 && $0.mode != .front }).randomElement() {
            bubbles.append(Bubble(cat: cat, text: text, life: 3))
        }
    }

    // MARK: - Update

    var extrasLively: Bool {
        if extras.laser.active || extras.mouse != nil || extras.bowl != nil { return true }
        let moving: [CatMode] = [.eatGo, .boxGo, .warmGo, .laserChase, .mouseHunt, .wave]
        return cats.contains { moving.contains($0.mode) }
    }

    /// Falling leaves and snow look fine at the calm frame rate; only a wiggling chubby cat in the box needs more
    var extrasAmbient: Bool {
        return extras.box?.occupant?.breed.fat == true
    }

    func updateExtras(_ dt: CGFloat, points: [TouchPoint]) {
        let e = extras
        if t >= e.calendarCheckAt {
            e.calendarCheckAt = t + 600
            e.calendar = CatCalendar.now()
        }
        CatDecor.hats = AppSettings.seasons && e.calendar.newYear
        checkWordPause()
        updateSeasons(dt)
        updateLaser(dt)
        updateMouse(dt)
        updateBox(dt)
        if let bowl = e.bowl {
            bowl.life -= dt
            if bowl.life <= 0 { e.bowl = nil }
        }
        if t >= e.batteryCheckAt {
            e.batteryCheckAt = t + 20
            checkBattery()
        }
        if let end = e.pomodoroEnd, Date() >= end, let cat = e.pomodoroCat {
            e.pomodoroEnd = nil
            cat.setMode(.stretch, 1.2)
            cat.happy = 1.5
            bubbles.append(Bubble(cat: cat, text: tr("перерыв!", "break time!"), life: 6))
            CatSounds.shared.play(.meow, pan: pan(cat.x))
            HapticFeedback.instance.tap(type: .strong)
        }
        CatSounds.shared.setPurr(cats.contains { $0.petT > 0.35 }, pan: pan(cats.first { $0.petT > 0.35 }?.x ?? width / 2))
        CatSounds.shared.tick()
    }

    private func updateLaser(_ dt: CGFloat) {
        syncTrackpad()
        var laser = extras.laser
        defer { extras.laser = laser }
        // one finger moving the cursor; a click, a resting finger or a two-finger scroll is not a laser
        guard AppSettings.trackpadLaser, let finger = CatTrackpad.shared.finger, finger.count == 1,
              CACurrentMediaTime() - finger.time < 0.25 else {
            laser.active = false
            laser.touchStart = nil
            return
        }
        let target = laserPoint(finger)
        guard let start = laser.touchStart else {
            laser.touchStart = (finger.x, finger.y)
            laser.lastMove = t
            return
        }
        if !laser.active {
            guard hypot(finger.x - start.x, finger.y - start.y) > 0.03 else { return }
            laser.active = true
            laser.lastMove = t
            laser.x = target.x
            laser.y = target.y
        }
        if hypot(target.x - laser.x, target.y - laser.y) > 0.3 { laser.lastMove = t }
        laser.x += (target.x - laser.x) * min(1, dt * 30)
        laser.y += (target.y - laser.y) * min(1, dt * 30)
        if t - laser.lastMove > 3 {
            laser.active = false // the finger just rests there
            laser.touchStart = (finger.x, finger.y)
            return
        }
        guard laser.active else { return }
        for cat in cats where [.sit, .walk, .groom, .run, .boop].contains(cat.mode) && cat.breed.playful > 0.35 &&
            abs(cat.x - laser.x) < 400 && Bool.random() {
            cat.setMode(.laserChase, 99)
        }
    }

    /// The trackpad sits right under the middle of the keyboard: its width maps onto the part of the bar above it,
    /// its depth onto the bar's height (the far edge is the top)
    private func laserPoint(_ f: CatTrackpad.Finger) -> CGPoint {
        let mm = CatTrackpad.shared.widthMM > 0 ? CatTrackpad.shared.widthMM : 160
        let units = 7.25 + (f.x - 0.5) * mm / 19 // in key widths, like the keys above it
        let x = clamp((units - 1.05) / (13.45 - 1.05), 0.01, 0.99) * width
        let y = clamp(ground - 2 - f.y * (ground - 6), 3, ground - 2)
        return CGPoint(x: x, y: y)
    }

    func syncTrackpad() {
        if AppSettings.trackpadLaser && !paused && !systemAsleep {
            CatTrackpad.shared.start()
        } else {
            CatTrackpad.shared.stop()
        }
    }

    private func updateMouse(_ dt: CGFloat) {
        let e = extras
        if e.mouse == nil && t >= e.nextMouseAt {
            e.nextMouseAt = t + rnd(300, 600)
            releaseMouse(towards: rnd(0, width))
        }
        guard let m = e.mouse else { return }
        m.scared = max(0, m.scared - dt)
        let chased = cats.contains { $0.mode == .mouseHunt && abs($0.x - m.x) < 40 }
        if m.pause > 0 && !chased {
            m.pause -= dt
        } else {
            let speed: CGFloat = m.scared > 0 ? 150 : (chased ? 95 : 55)
            m.x += m.dir * speed * dt
            m.frame += dt * speed * 0.3
            if !chased && rnd(0, 1) < dt * 0.5 { m.pause = rnd(0.4, 1.4) }
        }
        if m.x < -20 || m.x > width + 20 {
            e.mouse = nil
            return
        }
        if m.hunter == nil, let hunter = cats.filter({ [.sit, .walk, .groom, .run, .boop].contains($0.mode) && $0.breed.playful > 0.4 &&
            abs($0.x - m.x) < 220 }).min(by: { abs($0.x - m.x) < abs($1.x - m.x) }) {
            m.hunter = hunter
            hunter.setMode(.mouseHunt, 99)
        }
        // a pounce that lands on the mouse
        for cat in cats where cat.mode == .jump {
            guard let j = cat.jump, j.t > 0.7, abs(cat.x - m.x) < 8 else { continue }
            if Bool.random() {
                burst(m.x, height - 3)
                spawn(.heart, cat.x + cat.dir * 4, 5)
                cat.happy = 1.2
                CatSounds.shared.play(.mrrp, pan: pan(cat.x))
                e.mouse = nil
            } else {
                m.dir = cat.x > m.x ? -1 : 1 // escaped!
                m.scared = 2
                spawn(.bang, cat.x, 8)
            }
            return
        }
    }

    private func updateBox(_ dt: CGFloat) {
        let e = extras
        if e.box == nil && t >= e.nextBoxAt {
            e.nextBoxAt = t + rnd(900, 1800)
            putBox(at: rnd(40, width - 40))
        }
        guard let box = e.box else { return }
        box.life -= dt
        if box.life <= 0 {
            if let cat = box.occupant, cat.mode == .inBox || cat.mode == .boxGo {
                cat.jy = 0
                cat.setMode(.sit, 1.5)
            }
            e.box = nil
            return
        }
        if box.occupant == nil {
            box.rest -= dt
            if box.rest <= 0, let cat = idleCats(box.x, within: 400).filter({ $0.mode != .loaf })
                .min(by: { abs($0.x - box.x) < abs($1.x - box.x) }) {
                box.occupant = cat
                box.rest = rnd(2, 6)
                cat.setMode(.boxGo, 99)
            }
        }
    }

    private func updateSeasons(_ dt: CGFloat) {
        guard AppSettings.seasons else {
            extras.flakes.removeAll()
            return
        }
        let cal = extras.calendar
        extras.flakeT -= dt
        if extras.flakeT <= 0 {
            switch cal.season {
            case .winter:
                extras.flakeT = 0.25
                extras.flakes.append(Flake(kind: .snow, x: rnd(0, width), y: -2, vx: rnd(-2, 2), vy: rnd(4, 8), phase: rnd(0, 6),
                                           color: RGB(0xF4F7FF)))
            case .autumn:
                extras.flakeT = rnd(1.2, 2.6)
                let colors: [UInt32] = [0xE0752B, 0xC9452B, 0xE8B23A, 0xB8642A]
                extras.flakes.append(Flake(kind: .leaf, x: rnd(0, width), y: -2, vx: rnd(4, 10), vy: rnd(4, 7), phase: rnd(0, 6),
                                           color: RGB(colors.randomElement()!)))
            case .spring:
                extras.flakeT = rnd(1.5, 3)
                extras.flakes.append(Flake(kind: .petal, x: rnd(0, width), y: -2, vx: rnd(2, 7), vy: rnd(3, 5), phase: rnd(0, 6),
                                           color: RGB(0xF6B8CC)))
            case .summer:
                extras.flakeT = rnd(15, 30)
                let colors: [UInt32] = [0xF2C94C, 0x7FB8F0, 0xF2994A, 0xBB86FC]
                let fromLeft = Bool.random()
                extras.flakes.append(Flake(kind: .butterfly, x: fromLeft ? -4 : width + 4, y: rnd(5, 14), vx: fromLeft ? rnd(10, 18) : -rnd(10, 18),
                                           vy: 0, phase: rnd(0, 6), color: RGB(colors.randomElement()!)))
            }
            if cal.halloween && dark > 0.3 && rnd(0, 1) < 0.05 {
                let fromLeft = Bool.random()
                extras.flakes.append(Flake(kind: .bat, x: fromLeft ? -4 : width + 4, y: rnd(3, 8), vx: fromLeft ? 30 : -30, vy: 0,
                                           phase: 0, color: RGB(0x5A4A7A)))
            }
            if cal.valentine && rnd(0, 1) < 0.03 { spawn(.heart, rnd(10, width - 10), 14) }
        }
        for i in extras.flakes.indices {
            var f = extras.flakes[i]
            f.phase += dt
            switch f.kind {
            case .snow, .petal, .leaf:
                f.x += (f.vx + sin(f.phase * 1.7) * 3) * dt
                f.y += f.vy * dt
            case .butterfly:
                f.x += f.vx * dt
                f.y += sin(f.phase * 3) * 6 * dt
            case .bat:
                f.x += f.vx * dt
                f.y += sin(f.phase * 5) * 4 * dt
            }
            extras.flakes[i] = f
        }
        extras.flakes.removeAll { $0.y > height + 2 || $0.x < -8 || $0.x > width + 8 }
        if extras.flakes.count > 60 { extras.flakes.removeFirst(extras.flakes.count - 60) }
    }

    // MARK: - Battery

    private func checkBattery() {
        let e = extras
        let wasPlugged = e.pluggedIn
        (e.batteryLevel, e.pluggedIn) = CatDevices.battery()
        if e.pluggedIn && !cats.contains(where: { $0.mode == .warm || $0.mode == .warmGo }),
           let cat = cats.filter({ [.sit, .walk, .groom, .loaf, .boop].contains($0.mode) && !$0.removing }).min(by: { $0.x < $1.x }) {
            cat.setMode(.warmGo, 99) // the charging port is on the left: warm spot
            if !wasPlugged { bubbles.append(Bubble(cat: cat, text: tr("тепло!", "warm!"), life: 2)) }
        }
    }

    // MARK: - Cats doing extra things

    func updateExtraMode(_ cat: Cat, _ dt: CGFloat) {
        let e = extras
        switch cat.mode {
        case .laserChase:
            guard e.laser.active else {
                cat.setMode(.sit, 1.5)
                return
            }
            if abs(e.laser.x - cat.x) < 8 {
                // a pounce on the floor, or a leap as high as the dot
                let h = clamp(ground - e.laser.y - 6, 4, 15)
                cat.prey = nil
                cat.jump = Jump(from: cat.x, to: clamp(e.laser.x + cat.dir * 3, 10, width - 10), t: 0, h: h)
                cat.setMode(.jump, 0.5)
            } else {
                moveTo(cat, e.laser.x, 95, dt)
            }
        case .mouseHunt:
            guard let m = e.mouse, m.hunter === cat else {
                cat.setMode(.sit, 1.2)
                return
            }
            if abs(m.x - cat.x) < 14 {
                cat.tx = m.x + m.dir * 8
                cat.prey = nil
                cat.setMode(.crouch, 0.25)
                m.hunter = nil
            } else {
                moveTo(cat, m.x - m.dir * 4, 85, dt)
            }
        case .eatGo:
            guard let bowl = e.bowl else {
                cat.setMode(.sit, 1)
                return
            }
            if moveTo(cat, clamp(bowl.x + cat.extraT, 10, width - 10), 75, dt) {
                cat.dir = bowl.x >= cat.x ? 1 : -1
                cat.setMode(.eat, 99)
            }
        case .eat:
            if e.bowl == nil {
                cat.happy = 1.2
                spawn(.heart, cat.x + cat.dir * 4, 6)
                cat.setMode(.groom, rnd(2, 4))
            }
        case .wave, .sulk:
            if cat.mt >= cat.dur { cat.setMode(.sit, 1.5) }
        case .boxGo:
            guard let box = e.box, box.occupant === cat else {
                cat.setMode(.sit, 1)
                return
            }
            if moveTo(cat, box.x, 60, dt) {
                puff(box.x)
                cat.setMode(.inBox, rnd(6, 14))
                if cat.breed.fat { spawn(.bang, cat.x + 6, 8) } // doesn't quite fit
            }
        case .inBox:
            guard let box = e.box, box.occupant === cat else {
                cat.jy = 0
                cat.setMode(.sit, 1)
                return
            }
            cat.x = box.x + (cat.breed.fat ? sin(t * 22) * 0.6 : 0)
            cat.jy = cat.breed.fat ? -2.5 : -6.5 // sinks into the box; a chubby one gets stuck
            if cat.mt >= cat.dur {
                cat.jy = 0
                box.occupant = nil
                cat.x = clamp(box.x + (Bool.random() ? 14 : -14), 10, width - 10)
                puff(cat.x)
                cat.setMode(.sit, 1.5)
            }
        case .pomodoro:
            if e.pomodoroEnd == nil || e.pomodoroCat !== cat { cat.setMode(.stretch, 1) }
        case .warmGo:
            if !e.pluggedIn {
                cat.setMode(.sit, 1)
            } else if moveTo(cat, 16, 55, dt) {
                cat.setMode(.warm, 99)
            }
        case .warm:
            if !e.pluggedIn { cat.setMode(.stretch, 1.2) }
        default:
            break
        }
    }

    func tapExtra(_ cat: Cat) {
        switch cat.mode {
        case .pomodoro:
            if let end = extras.pomodoroEnd {
                let left = max(1, Int(ceil(end.timeIntervalSinceNow / 60)))
                bubbles.append(Bubble(cat: cat, text: tr("ещё \(left) мин", "\(left) min left"), life: 2.5))
            }
        case .inBox:
            cat.extraT = 0
            cat.dur = cat.mt // hop out now
        default:
            spawn(.heart, cat.x + cat.dir * 4, 6)
        }
    }

    /// Hook for the cats' own choices: kittens follow their parent, low battery makes everyone sleepy
    func extraNext(_ cat: Cat) -> Bool {
        if cat.breed.kitten, let pid = cat.breed.parent,
           let parent = cats.first(where: { $0.breed.key == pid && $0.mode != .exit && !$0.removing }) {
            if parent.mode == .loaf || parent.mode == .warm {
                if abs(parent.x - cat.x) < 18 {
                    cat.setMode(.loaf, rnd(8, 16))
                } else {
                    cat.tx = clamp(parent.x - 12, 10, width - 10)
                    cat.setMode(.walk, 99)
                }
                return true
            }
            if rnd(0, 1) < 0.65 {
                cat.tx = clamp(parent.x - parent.dir * rnd(10, 16), 10, width - 10)
                cat.setMode(abs(parent.x - cat.x) > 80 ? .run : .walk, 99)
                return true
            }
        }
        if extras.lowBattery && cat.mode != .loaf && rnd(0, 1) < 0.4 {
            cat.setMode(.loaf, rnd(10, 20))
            return true
        }
        return false
    }

    // MARK: - Drawing

    private func fill(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: RGB, _ a: CGFloat = 1, night: CGFloat = 0.55) {
        let col = c.mixed(RGB(r: 6, g: 9, b: 26), dark * night)
        ctx.setFillColor(red: col.r / 255, green: col.g / 255, blue: col.b / 255, alpha: a)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Behind the cats: pumpkins, the inside of the box, the bowl, the mouse
    func drawExtrasBack(_ ctx: CGContext) {
        let g = height
        if AppSettings.seasons && extras.calendar.halloween {
            for k: CGFloat in [0.12, 0.58, 0.91] {
                let x = (width * k).rounded()
                fill(ctx, x - 3, g - 5, 7, 4, RGB(0xE8822A), night: 0.4)
                fill(ctx, x - 2, g - 6, 5, 1, RGB(0xE8822A), night: 0.4)
                fill(ctx, x - 1, g - 5, 1, 4, RGB(0xC2621A), night: 0.4)
                fill(ctx, x + 1, g - 5, 1, 4, RGB(0xC2621A), night: 0.4)
                fill(ctx, x, g - 7.5, 1, 1.5, RGB(0x5A8A3A), night: 0.4)
                if dark > 0.3 { // jack-o'-lantern face glows at night
                    fill(ctx, x - 2, g - 4, 1, 1, RGB(0xFFD860), night: 0)
                    fill(ctx, x + 2, g - 4, 1, 1, RGB(0xFFD860), night: 0)
                    fill(ctx, x - 1, g - 2.5, 3, 0.8, RGB(0xFFD860), night: 0)
                }
            }
        }
        if let box = extras.box {
            fill(ctx, box.x - 10, g - 11, 20, 3, RGB(0x6E4A2A))
        }
        if let bowl = extras.bowl {
            let x = bowl.x
            if bowl.life > 3 {
                fill(ctx, x - 2.5, g - 4.5, 5, 1.5, RGB(0xF0A060))
                fill(ctx, x + 2.5, g - 5, 1, 2.5, RGB(0xF0A060))
            }
            fill(ctx, x - 5, g - 3, 10, 2.5, RGB(0x4A8CC8))
            fill(ctx, x - 5, g - 3, 10, 0.6, RGB(0x7FB8F0))
        }
        if let m = extras.mouse {
            let d = m.dir, x = m.x, step = Int(m.frame) % 2
            fill(ctx, x - 3, g - 3.5, 6, 2.5, RGB(0x9A9AA6))
            fill(ctx, x + d * 3 - (d > 0 ? 0 : 1.5), g - 3, 1.5, 1.5, RGB(0x9A9AA6))
            fill(ctx, x + d * 1.5 - 0.5, g - 4.5, 1, 1, RGB(0xE8A0B0))
            fill(ctx, x + d * 3.5 - 0.3, g - 2.8, 0.6, 0.6, RGB(0x141418), night: 0)
            fill(ctx, x - d * 3 - (d > 0 ? 3 : 0), g - 2, 3, 0.5, RGB(0xC8A0A8))
            fill(ctx, x - 2 + CGFloat(step), g - 1, 0.8, 0.8, RGB(0x8A8A96))
            fill(ctx, x + 1 - CGFloat(step), g - 1, 0.8, 0.8, RGB(0x8A8A96))
        }
    }

    /// In front of the cats: the box front, the laser dot, falling snow and leaves, timers
    func drawExtrasFront(_ ctx: CGContext) {
        let g = height
        if let box = extras.box {
            let x = box.x
            fill(ctx, x - 11, g - 8.5, 22, 8.5, RGB(0xC08A52))
            fill(ctx, x - 11, g - 8.5, 22, 1, RGB(0xD9A86C))
            fill(ctx, x - 1, g - 8.5, 2, 8.5, RGB(0xE3CFA4))
            fill(ctx, x - 14, g - 11, 3, 2.5, RGB(0xB07A46))
            fill(ctx, x + 11, g - 11, 3, 2.5, RGB(0xB07A46))
        }
        for cat in cats where cat.mode == .warm { // warm air from the charging port
            for k in 0 ..< 3 {
                let phase = (t * 0.6 + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
                fill(ctx, cat.x - 2 + CGFloat(k) * 3 + sin(t * 3 + CGFloat(k)) * 0.8, 10 - phase * 8, 1, 1, RGB(0xFFB070), 0.6 * (1 - phase), night: 0)
            }
        }
        if let end = extras.pomodoroEnd, let cat = extras.pomodoroCat {
            let left = String(max(1, Int(ceil(end.timeIntervalSinceNow / 60))))
            let sc: CGFloat = 0.6
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.75)
            for (i, ch) in left.enumerated() {
                let cx = cat.x + 8 + CGFloat(i) * 4.2
                for (px, py) in GlyphCache.pixels(String(ch)) {
                    ctx.fill(CGRect(x: cx + CGFloat(px) * sc, y: 12 + CGFloat(py) * sc, width: sc + 0.02, height: sc + 0.02))
                }
            }
        }
        for f in extras.flakes {
            switch f.kind {
            case .snow:
                fill(ctx, f.x, f.y, 0.8, 0.8, f.color, 0.85, night: 0.1)
            case .petal:
                fill(ctx, f.x, f.y, 1, 0.7, f.color, 0.9, night: 0.3)
            case .leaf:
                let flat = sin(f.phase * 4) > 0
                fill(ctx, f.x, f.y, flat ? 1.6 : 0.8, flat ? 0.8 : 1.6, f.color, 1, night: 0.4)
            case .butterfly:
                let open = sin(f.phase * 18) > 0
                fill(ctx, f.x - (open ? 1.5 : 0.7), f.y, open ? 3 : 1.4, 1.2, f.color, 1, night: 0.4)
                fill(ctx, f.x - 0.3, f.y - 0.4, 0.6, 2, RGB(0x2A2A2A), 1, night: 0.4)
            case .bat:
                let up = sin(f.phase * 20) > 0
                fill(ctx, f.x - 2.5, f.y + (up ? -1 : 0.5), 2, 0.8, f.color, 1, night: 0)
                fill(ctx, f.x + 0.5, f.y + (up ? -1 : 0.5), 2, 0.8, f.color, 1, night: 0)
                fill(ctx, f.x - 0.5, f.y, 1, 1.2, f.color, 1, night: 0)
            }
        }
        if extras.laser.active {
            let x = extras.laser.x, y = extras.laser.y
            ctx.setFillColor(red: 1, green: 0.15, blue: 0.12, alpha: 0.22)
            ctx.fillEllipse(in: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9))
            ctx.setFillColor(red: 1, green: 0.2, blue: 0.16, alpha: 0.5)
            ctx.fillEllipse(in: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8))
            ctx.setFillColor(red: 1, green: 0.35, blue: 0.3, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
            ctx.setFillColor(red: 1, green: 0.85, blue: 0.8, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
        }
    }
}

// MARK: - System state

enum CatDevices {
    static func battery() -> (level: CGFloat, pluggedIn: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (1, true) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let maxCap = d[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (CGFloat(current) / CGFloat(maxCap), plugged)
        }
        return (1, true)
    }

}
