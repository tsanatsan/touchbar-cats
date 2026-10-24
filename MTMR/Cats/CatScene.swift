//
//  CatScene.swift
//  MTMR
//
//  The cats' world on the Touch Bar: behavior, typed letters as fireflies, touches,
//  "кс-кс", "мяу", Backspace, the yarn ball, memory between launches.
//  One shared scene survives Touch Bar reloads; CatsBarItem views only draw it.
//

import AppKit
import Carbon
import IOKit.ps

enum CatMode {
    case sit, walk, run, chase, hunt, crouch, jump, loaf, stretch, yawn, groom, munch
    case boop, boopGo, attend, front, swatGo, swat, ballChase, fetch, carry, come, enter, exit
    // toys, words and helpers (CatExtras.swift)
    case eatGo, eat, wave, sulk, boxGo, inBox, pomodoro, warmGo, warm
    case laserChase, mouseHunt
}

private let extraModes: Set<CatMode> = [.eatGo, .eat, .wave, .sulk, .boxGo, .inBox, .pomodoro, .warmGo, .warm, .laserChase, .mouseHunt]

enum FlyState {
    case rise, hover, drop, knocked, fall
}

final class Fly {
    let ch: String?
    let glyph: [(Int, Int)]
    var x: CGFloat
    var y: CGFloat
    var ty: CGFloat
    var t: CGFloat = 0
    var vx: CGFloat
    var vy: CGFloat = 0
    let phase: CGFloat
    var alive = true
    var state = FlyState.rise
    var life: CGFloat
    var rot: CGFloat = 0
    var spin: CGFloat = 0
    var a: CGFloat = 1
    var dropT: CGFloat = 0
    var knockT: CGFloat = 0
    weak var hunter: Cat?
    weak var swatter: Cat?

    init(ch: String?, x: CGFloat, y: CGFloat, ty: CGFloat, life: CGFloat) {
        self.ch = ch
        glyph = ch.map { GlyphCache.pixels($0) } ?? []
        self.x = x
        self.y = y
        self.ty = ty
        self.life = life
        vx = .random(in: -5 ... 5)
        phase = .random(in: 0 ... 6)
    }

    var isLit: Bool { return state == .rise || state == .hover }
}

struct Jump {
    var from: CGFloat
    var to: CGFloat
    var t: CGFloat
    var h: CGFloat
}

final class Cat {
    var breed: Breed
    let index: Int
    let seed: Int
    var x: CGFloat = 0
    var dir: CGFloat = 1
    var mode = CatMode.sit
    var mt: CGFloat = 0
    var dur: CGFloat = 1
    var tx: CGFloat = 0
    var frame: CGFloat = 0
    var jy: CGFloat = 0
    var jump: Jump?
    var happy: CGFloat = 0
    var petT: CGFloat = 0
    var heartT: CGFloat = 0
    var zT: CGFloat = 0
    var prey: Fly?
    var target: Fly?
    weak var other: Cat?
    var disturb: CGFloat = 0
    var look: CGFloat = 0
    var earT: CGFloat = -1
    var land: CGFloat = 0
    var done = false
    var caught = false
    var cl: CGFloat = 0 // how close to the glass in the front pose, 0...1
    var pawT: CGFloat = 0
    var boopT: CGFloat = 0
    var pawCool: CGFloat = .random(in: 1 ... 3)
    var meowT: CGFloat = 0
    var carrying = false
    var removing = false
    var nameShown = false
    var petIdle: CGFloat = 0
    var affection: CGFloat = 0
    var extraT: CGFloat = 0

    var isExtraMode: Bool { return extraModes.contains(mode) }
    var slot = 0 // place in the row at the glass

    init(breed: Breed, index: Int) {
        self.breed = breed
        self.index = index
        seed = (index * 37 + 11) % 97
    }

    func setMode(_ m: CatMode, _ duration: CGFloat = 1) {
        mode = m
        mt = 0
        dur = duration
        done = false
    }
}

struct Effect {
    enum Kind { case heart, z, bang }
    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var life: CGFloat = 1
}

struct Particle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: CGFloat = 1
}

final class Bubble {
    let cat: Cat
    let text: String
    let total: CGFloat
    var life: CGFloat

    init(cat: Cat, text: String, life: CGFloat = 1.9) {
        self.cat = cat
        self.text = text
        total = life
        self.life = life
    }
}

final class YarnBall {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat = 0
    var rot: CGFloat = 0
    var held = false

    init(x: CGFloat, y: CGFloat, vx: CGFloat) {
        self.x = x
        self.y = y
        self.vx = vx
    }
}

struct TouchPoint {
    var x: CGFloat
    var startX: CGFloat = 0
    var vx: CGFloat = 0
    var lastMove: CFTimeInterval
    var start: CFTimeInterval
}

private func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { return .random(in: a ... b) }
private func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { return max(a, min(b, v)) }

final class CatScene {
    static let shared = CatScene()

    let height: CGFloat = 30
    var width: CGFloat = 1004 {
        didSet {
            guard abs(width - oldValue) > 1 else { return }
            // the bar got narrower (e.g. "width" in the preset): bring wandering cats back in
            for cat in cats where cat.mode != .exit && (cat.x > width - 14 || cat.tx > width - 14) {
                cat.x = min(cat.x, width + 20)
                cat.tx = rnd(30, max(31, width - 30))
                cat.setMode(.enter, 99)
            }
        }
    }
    var ground: CGFloat { return height - 0.5 }
    let floorY: CGFloat = 23
    var ballGroundY: CGFloat { return height - 4.5 }

    private(set) var roster: [Cat]
    private var deletedIds: Set<String> = []
    private(set) var cats: [Cat] = []
    var flies: [Fly] = []
    var effects: [Effect] = []
    var sparks: [Particle] = []
    var dust: [Particle] = []
    var bubbles: [Bubble] = []
    var ball: YarnBall?
    let extras = CatExtras()
    var pending: [(at: CGFloat, run: () -> Void)] = []
    private var history: [(ch: String, x: CGFloat)] = []
    private var typed = ""
    private var ksCount = 0
    private var lastKs: CGFloat = -99
    private(set) var ksTarget: CGFloat = 0
    private(set) var t: CGFloat = 0
    private(set) var dark: CGFloat = 0
    private(set) var paused: Bool
    private var exitCompletion: (() -> Void)?
    private var exitDeadline: CGFloat = 0
    private var lastAdvance: CFTimeInterval = 0
    private(set) var touches: [Int: TouchPoint] = [:]
    private var taps: [CGFloat] = []
    private var doubleTaps: [CGFloat] = []
    private var lastTap: (x: CGFloat, time: CFTimeInterval)?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var trustCheckAt: CGFloat = 0
    private var hintAt: CGFloat = 4
    /// Without Accessibility macOS does not pass other apps' key presses to MTMR
    private(set) var keyboardAllowed = AXIsProcessTrusted()
    private var saveAt: CGFloat?
    private var powerCheckAt: CGFloat = 0
    private(set) var onBattery = false
    private(set) var systemAsleep = false

    /// 0 – by the clock, 1 – always night, 2 – always day
    var nightMode: Int {
        didSet { UserDefaults.standard.set(nightMode, forKey: "cats.night") }
    }

    private(set) var caughtToday: Int

    private init() {
        let breeds = catBreeds + CustomCatStore.load().prefix(maxCats - catBreeds.count).map { $0.breed }
        roster = breeds.enumerated().map { Cat(breed: $0.element, index: $0.offset) }
        let defaults = UserDefaults.standard
        nightMode = defaults.integer(forKey: "cats.night")
        let today = CatScene.dayString()
        caughtToday = defaults.string(forKey: "cats.caught.day") == today ? defaults.integer(forKey: "cats.caught.count") : 0
        let all = roster
        // settings are stored by cat id; older versions stored array positions of the ten built-in cats
        var affection = defaults.dictionary(forKey: "cats.affectionById") as? [String: Double] ?? [:]
        if affection.isEmpty, let old = defaults.array(forKey: "cats.affection") as? [Double] {
            for (cat, value) in zip(all, old) { affection[cat.breed.key] = value }
        }
        for cat in all { cat.affection = CGFloat(affection[cat.breed.key] ?? 0) }
        var enabled = defaults.stringArray(forKey: "cats.enabledIds")
        if enabled == nil, let old = defaults.array(forKey: "cats.enabled") as? [Int] {
            enabled = old.filter { $0 >= 0 && $0 < catBreeds.count }.map { catBreeds[$0].key }
        }
        let ids = enabled ?? all.map { $0.breed.key }
        paused = AppSettings.nativeTouchBar
        cats = all.filter { ids.contains($0.breed.key) }
        placeOffscreen()
        if !paused { walkIn() }
        installMonitors()
    }

    // MARK: - Public controls

    var activeCount: Int { return cats.filter { !$0.removing }.count }
    var customCount: Int { return roster.filter { $0.breed.custom && !deletedIds.contains($0.breed.key) }.count }
    var canAddCustomCat: Bool { return roster.count - deletedIds.count < maxCats }

    func isEnabled(_ id: String) -> Bool {
        return cats.contains { $0.breed.key == id && !$0.removing }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let cat = roster.first(where: { $0.breed.key == id }), !deletedIds.contains(id) else { return }
        if on {
            guard !cats.contains(where: { $0 === cat }) || cat.removing else { return }
            cat.removing = false
            if !cats.contains(where: { $0 === cat }) {
                resetState(cat)
                cat.x = Bool.random() ? -22 : width + 22
                cats.append(cat)
            }
            cat.tx = rnd(30, max(31, width - 30))
            cat.setMode(.enter, 99)
        } else {
            guard cats.contains(where: { $0 === cat }), activeCount > 1 else { return }
            cat.removing = true
            sendOff(cat)
        }
        saveSoon()
    }

    func addCat() {
        if let next = roster.first(where: { !isEnabled($0.breed.key) && !deletedIds.contains($0.breed.key) }) {
            setEnabled(next.breed.key, true)
        }
    }

    func removeCat() {
        if let last = cats.last(where: { !$0.removing }) { setEnabled(last.breed.key, false) }
    }

    /// A cat made in the workshop moves in from the edge
    func addCustomCat(_ record: CustomCat) {
        guard canAddCustomCat else { return }
        var stored = CustomCatStore.load().filter { $0.id != record.id }
        stored.append(record)
        CustomCatStore.save(stored)
        let cat = Cat(breed: record.breed, index: roster.count)
        roster.append(cat)
        setEnabled(cat.breed.key, true)
        save()
    }

    /// The workshop saved changes to one of your cats
    func updateCustomCat(_ record: CustomCat) {
        var stored = CustomCatStore.load()
        if let i = stored.firstIndex(where: { $0.id == record.id }) { stored[i] = record } else { stored.append(record) }
        CustomCatStore.save(stored)
        roster.first { $0.breed.key == record.id }?.breed = record.breed
        saveSoon()
    }

    func deleteCustomCat(_ id: String) {
        CustomCatStore.save(CustomCatStore.load().filter { $0.id != id })
        guard let cat = roster.first(where: { $0.breed.key == id }) else { return }
        deletedIds.insert(id)
        if cats.contains(where: { $0 === cat }) {
            cat.removing = true
            sendOff(cat)
        } else {
            roster.removeAll { $0 === cat }
            deletedIds.remove(id)
        }
        saveSoon()
    }

    /// Cats run off the edges, then `completion` (used before showing the system Touch Bar)
    func runAway(completion: @escaping () -> Void) {
        guard !paused, !cats.isEmpty else {
            paused = true
            completion()
            return
        }
        for cat in cats { sendOff(cat) }
        exitCompletion = completion
        exitDeadline = t + 1.3
    }

    /// Cats come back in from the edges
    func walkIn() {
        paused = false
        exitCompletion = nil
        lastAdvance = CACurrentMediaTime()
        placeOffscreen()
        for cat in cats where !cat.removing {
            cat.tx = rnd(30, max(31, width - 30))
            cat.setMode(.enter, 99)
        }
    }

    func setSystemAsleep(_ asleep: Bool) {
        systemAsleep = asleep
        lastAdvance = CACurrentMediaTime()
    }

    enum Activity {
        case calm // everyone rests: blinking and tails only
        case ambient // cats stroll around
        case lively // fireflies, touches, jumps, running, "кс кс"
    }

    /// How fast the bar needs to redraw right now; the view picks the frame rate from it
    var activity: Activity {
        if extrasLively || CatRecorder.shared.isRecording { return .lively }
        if !flies.isEmpty || !sparks.isEmpty || !dust.isEmpty || !touches.isEmpty || exitCompletion != nil { return .lively }
        if effects.contains(where: { $0.kind != .z }) || !bubbles.isEmpty { return .lively }
        if let ball = ball, ball.held || abs(ball.vx) > 1 || ball.y < ballGroundY - 0.5 { return .lively }
        let fast: [CatMode] = [.run, .chase, .hunt, .crouch, .jump, .attend, .swatGo, .swat, .ballChase, .fetch, .carry,
                               .come, .enter, .exit]
        var strolling = false
        for cat in cats {
            if fast.contains(cat.mode) || cat.land > 0 || cat.boopT > 0 || cat.pawT > 0 { return .lively }
            if cat.mode == .front && abs(cat.cl - ksTarget) > 0.01 { return .lively }
            if cat.mode == .walk || cat.mode == .boopGo || cat.mode == .front || cat.happy > 0 { strolling = true }
        }
        return strolling || extrasAmbient ? .ambient : .calm
    }

    private func placeOffscreen() {
        for (i, cat) in cats.enumerated() {
            resetState(cat)
            cat.x = i % 2 == 0 ? -20 - CGFloat(i) * 8 : width + 20 + CGFloat(i) * 8
        }
    }

    func resetState(_ cat: Cat) {
        cat.prey = nil
        cat.target = nil
        cat.jy = 0
        cat.jump = nil
        cat.cl = 0
        cat.pawT = 0
        cat.carrying = false
        cat.happy = 0
        cat.setMode(.sit, 1)
    }

    private func sendOff(_ cat: Cat) {
        cat.prey = nil
        cat.target = nil
        cat.jy = 0
        cat.cl = 0
        if cat.carrying {
            cat.carrying = false
            ball = nil
        }
        cat.tx = cat.x < width / 2 ? -26 : width + 26
        cat.setMode(.exit, 99)
    }

    // MARK: - Time

    /// Advances the world to `now`; safe to call from several views in the same frame
    func advance(to now: CFTimeInterval) {
        if lastAdvance == 0 { lastAdvance = now }
        let dt = CGFloat(min(0.05, now - lastAdvance))
        guard dt >= 0.002 else { return }
        lastAdvance = now
        guard !paused, !systemAsleep else { return }
        update(dt)
    }

    var isNight: Bool {
        if nightMode == 1 { return true }
        if nightMode == 2 { return false }
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 23 || h < 7
    }

    // MARK: - Keyboard

    private func installMonitors() {
        // Global key events need the Accessibility permission (MTMR already asks for it)
        installGlobalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleKey(e)
            return e
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.setSystemAsleep(true) }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.setSystemAsleep(false) }
        center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setSystemAsleep(true) }
        center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setSystemAsleep(false) }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.save() }
    }

    private func installGlobalMonitor() {
        if let old = globalMonitor { NSEvent.removeMonitor(old) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handleKey(e) }
    }

    /// Picks the keyboard up as soon as Accessibility is granted, no relaunch needed
    private func checkKeyboardAccess() {
        let allowed = AXIsProcessTrusted()
        if allowed != keyboardAllowed {
            keyboardAllowed = allowed
            if allowed { installGlobalMonitor() }
        }
        if !allowed && t >= hintAt, let cat = cats.filter({ $0.mode != .exit && $0.mode != .front && $0.x > 20 && $0.x < width - 20 }).randomElement() {
            hintAt = t + 45
            bubbles.append(Bubble(cat: cat, text: tr("нужен доступ", "need access"), life: 4))
        }
    }

    private static let keyUnits: [Int: CGFloat] = [
        kVK_ANSI_Grave: 0.5, kVK_ISO_Section: 0.5, kVK_ANSI_1: 1.5, kVK_ANSI_2: 2.5, kVK_ANSI_3: 3.5, kVK_ANSI_4: 4.5,
        kVK_ANSI_5: 5.5, kVK_ANSI_6: 6.5, kVK_ANSI_7: 7.5, kVK_ANSI_8: 8.5, kVK_ANSI_9: 9.5, kVK_ANSI_0: 10.5,
        kVK_ANSI_Minus: 11.5, kVK_ANSI_Equal: 12.5, kVK_Delete: 13.75,
        kVK_ANSI_Q: 2, kVK_ANSI_W: 3, kVK_ANSI_E: 4, kVK_ANSI_R: 5, kVK_ANSI_T: 6, kVK_ANSI_Y: 7, kVK_ANSI_U: 8,
        kVK_ANSI_I: 9, kVK_ANSI_O: 10, kVK_ANSI_P: 11, kVK_ANSI_LeftBracket: 12, kVK_ANSI_RightBracket: 13, kVK_ANSI_Backslash: 14,
        kVK_ANSI_A: 2.25, kVK_ANSI_S: 3.25, kVK_ANSI_D: 4.25, kVK_ANSI_F: 5.25, kVK_ANSI_G: 6.25, kVK_ANSI_H: 7.25,
        kVK_ANSI_J: 8.25, kVK_ANSI_K: 9.25, kVK_ANSI_L: 10.25, kVK_ANSI_Semicolon: 11.25, kVK_ANSI_Quote: 12.25, kVK_Return: 13.6,
        kVK_ANSI_Z: 2.75, kVK_ANSI_X: 3.75, kVK_ANSI_C: 4.75, kVK_ANSI_V: 5.75, kVK_ANSI_B: 6.75, kVK_ANSI_N: 7.75,
        kVK_ANSI_M: 8.75, kVK_ANSI_Comma: 9.75, kVK_ANSI_Period: 10.75, kVK_ANSI_Slash: 11.75, kVK_Space: 7,
    ]

    private lazy var isISO: Bool = KBGetLayoutType(Int16(LMGetKbdType())) == PhysicalKeyboardLayoutType(kKeyboardISO)

    /// Horizontal position on the bar right above the physical key.
    /// 13" MacBook Pro: the bar starts after the Esc key and ends before Touch ID.
    private func barX(forKey code: Int) -> CGFloat? {
        var u = CatScene.keyUnits[code]
        if isISO && code == kVK_ANSI_Grave { u = 1.75 } // on ISO boards this key sits left of Z
        guard let units = u else { return nil }
        return clamp((units - 1.05) / (13.45 - 1.05), 0.02, 0.98) * width
    }

    private func handleKey(_ event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return }
        keyPressed(code: Int(event.keyCode), characters: event.characters)
    }

    func keyPressed(code: Int, characters: String?) {
        guard !paused, !systemAsleep else { return }
        guard let x = barX(forKey: code) else { return }
        if code == kVK_Delete {
            backspace()
            wordBackspace()
            return
        }
        if code == kVK_Space {
            for _ in 0 ..< 3 { spawnFly(nil, x: x + rnd(-18, 18)) }
            endWord(x: x)
            return
        }
        let ch: String
        if code == kVK_Return {
            ch = "↵"
        } else {
            guard let typedChars = characters, typedChars.count == 1 else { return }
            ch = typedChars
        }
        if ch != "↵" { noteTyped() }
        if flies.count < 40 { spawnFly(ch, x: x) }
        let lower = ch.lowercased()
        if lower.range(of: "^[a-zа-яё]$", options: .regularExpression) != nil {
            history.append((ch, x))
            if history.count > 40 { history.removeFirst() }
            typed = String((typed + lower).suffix(16))
            checkWords(x: x)
            appendWord(lower, x: x)
        } else if lower.range(of: "^[0-9]$", options: .regularExpression) != nil {
            appendWord(lower, x: x)
        } else {
            endWord(x: x)
        }
    }

    private func checkWords(x: CGFloat) {
        if typed.hasSuffix("кс") || typed.hasSuffix("ks") {
            ks()
        } else if typed.hasSuffix("мяу") || typed.hasSuffix("meow") {
            typed = ""
            meowBack(x: x)
        } else if typed.hasSuffix("клубок") || typed.hasSuffix("yarn") {
            typed = ""
            dropBall(at: x)
        }
    }

    // MARK: - Words

    /// Every "кс" brings the cats closer to the glass
    private func ks() {
        if t - lastKs > 3.5 { ksCount = 0 }
        ksCount += 1
        lastKs = t
        if ksCount == 1 {
            for cat in cats where !cat.removing {
                cat.earT = 0.4
                cat.look = 2
            }
            return
        }
        ksTarget = min(1, CGFloat(ksCount - 1) * 0.25)
        if ksCount == 2 { assignSlots() }
        for cat in cats where !cat.removing && ![.attend, .front, .exit].contains(cat.mode) {
            if cat.mode == .loaf { spawn(.bang, cat.x + cat.dir * 6, 9) }
            if cat.carrying {
                cat.carrying = false
                ball = nil
            }
            cat.prey = nil
            cat.target = nil
            cat.jy = 0
            cat.setMode(.attend, 99)
        }
    }

    private func meowBack(x: CGFloat) {
        guard let cat = cats.filter({ !$0.removing && $0.mode != .exit }).min(by: { abs($0.x - x) < abs($1.x - x) }) else { return }
        pending.append((t + 0.45, { [weak self] in
            guard let self = self else { return }
            if cat.mode == .front {
                cat.meowT = 0.6
                return
            }
            if cat.mode == .loaf { cat.setMode(.sit, 2) }
            cat.dir = x >= cat.x ? 1 : -1
            cat.look = 1
            self.bubbles.append(Bubble(cat: cat, text: (isRussian ? ["мяу", "мяу!", "мрр?"] : ["meow", "meow!", "mrr?"]).randomElement()!))
            CatSounds.shared.play(.meow, pan: self.pan(cat.x))
        }))
    }

    private func backspace() {
        typed = String(typed.dropLast())
        var fly = flies.last(where: { $0.ch != nil && $0.ch != "↵" && $0.isLit })
        let last = history.popLast()
        if let f = fly {
            if let hunter = f.hunter, hunter.mode == .hunt { hunter.setMode(.sit, 1) }
            f.hunter?.prey = nil
            f.hunter = nil
        } else if let h = last {
            let f = Fly(ch: h.ch, x: h.x, y: floorY - 6, ty: 0, life: 99)
            flies.append(f)
            fly = f
        }
        guard let f = fly else { return }
        f.state = .drop
        f.dropT = 0
        let busy: [CatMode] = [.jump, .crouch, .swatGo, .swat, .loaf, .front, .attend, .exit, .enter, .carry, .fetch]
        if let cat = cats.filter({ !busy.contains($0.mode) && !$0.isExtraMode && abs($0.x - f.x) < 300 }).min(by: { abs($0.x - f.x) < abs($1.x - f.x) }) {
            cat.target = f
            cat.prey = nil
            f.swatter = cat
            cat.setMode(.swatGo, 99)
        }
    }

    private func spawnFly(_ ch: String?, x: CGFloat) {
        let f = Fly(ch: ch, x: x, y: height + 6, ty: rnd(5, 11), life: ch == nil ? 1.2 : 2.3)
        flies.append(f)
        if let ch = ch, ch != "↵", ksTarget == 0 {
            let hunters = cats.filter {
                [.sit, .walk, .groom, .run, .boop].contains($0.mode) && $0.breed.playful > 0.4 && abs($0.x - x) < 170 && $0.happy <= 0
            }
            if let hunter = hunters.min(by: { abs($0.x - x) < abs($1.x - x) }) {
                hunter.prey = f
                f.hunter = hunter
                hunter.setMode(.hunt, 99)
            }
        }
        for cat in cats {
            if cat.mode == .loaf && abs(cat.x - x) < 30 {
                cat.disturb += 1
                if cat.disturb > 2.5 {
                    cat.disturb = 0
                    spawn(.bang, cat.x + cat.dir * 6, 9)
                    cat.setMode(.stretch, 1)
                }
            } else if [.sit, .groom, .walk].contains(cat.mode) && abs(cat.x - x) < 120 {
                cat.dir = x >= cat.x ? 1 : -1
                cat.look = 1.2
            }
        }
    }

    // MARK: - Yarn ball

    private func dropBall(at x: CGFloat) {
        let ball = YarnBall(x: clamp(x, 6, width - 6), y: -4, vx: rnd(-20, 20))
        if let holder = cats.first(where: { $0.carrying }) { holder.carrying = false }
        self.ball = ball
    }

    private func fetchBall() {
        guard let ball = ball, !ball.held else { return }
        let busy: [CatMode] = [.jump, .crouch, .front, .attend, .exit, .enter, .carry, .fetch, .loaf]
        if let cat = cats.filter({ !busy.contains($0.mode) }).min(by: { abs($0.x - ball.x) < abs($1.x - ball.x) }) {
            cat.prey = nil
            cat.setMode(.fetch, 99)
        }
    }

    // MARK: - Touches (points along the bar)

    func touchBegan(id: Int, x: CGFloat) {
        let now = CACurrentMediaTime()
        touches[id] = TouchPoint(x: x, startX: x, lastMove: now, start: now)
        taps.append(x)
        if let last = lastTap, now - last.time < 0.35, abs(last.x - x) < 22 {
            doubleTaps.append(x)
            lastTap = nil
        } else {
            lastTap = (x, now)
        }
    }

    func touchMoved(id: Int, x: CGFloat) {
        guard var p = touches[id] else { return }
        let now = CACurrentMediaTime()
        let dt = max(0.001, now - p.lastMove)
        let v = (x - p.x) / CGFloat(dt)
        p.vx = p.vx * 0.6 + v * 0.4
        p.x = x
        p.lastMove = now
        touches[id] = p
        if let ball = ball, !ball.held, abs(ball.x - x) < 7, abs(p.vx) > 40 {
            ball.vx += clamp(p.vx * 0.5, -260, 260) * 0.3
        }
    }

    func touchEnded(id: Int) {
        touches.removeValue(forKey: id)
    }

    func recentVx(_ p: TouchPoint, _ now: CFTimeInterval) -> CGFloat {
        return now - p.lastMove < 0.12 ? p.vx : 0
    }

    // MARK: - Update

    func spawn(_ kind: Effect.Kind, _ x: CGFloat, _ y: CGFloat) {
        effects.append(Effect(kind: kind, x: x, y: y))
    }

    func puff(_ x: CGFloat) {
        for i in 0 ..< 7 {
            let s: CGFloat = i % 2 == 1 ? 1 : -1
            dust.append(Particle(x: x + s * rnd(2, 6), y: height - 1.2, vx: s * rnd(6, 18), vy: -rnd(1, 5)))
        }
    }

    func burst(_ x: CGFloat, _ y: CGFloat) {
        for _ in 0 ..< 12 {
            let a = rnd(0, 6.28), v = rnd(10, 28)
            sparks.append(Particle(x: x, y: y, vx: cos(a) * v, vy: sin(a) * v - 6))
        }
    }

    @discardableResult
    func moveTo(_ cat: Cat, _ tx: CGFloat, _ speed: CGFloat, _ dt: CGFloat) -> Bool {
        let d = tx - cat.x
        if abs(d) < 1.5 { return true }
        cat.dir = d > 0 ? 1 : -1
        let s = speed * cat.breed.speed
        cat.x += cat.dir * min(abs(d), s * dt)
        cat.frame += dt * s * 0.42
        return false
    }

    private func slotX(_ cat: Cat) -> CGFloat {
        let count = max(1, cats.filter { !$0.removing }.count)
        return width * (CGFloat(min(cat.slot, count - 1)) + 0.5) / CGFloat(count)
    }

    /// Each cat takes the nearest place in the row, keeping their left-to-right order
    private func assignSlots() {
        for (i, cat) in cats.filter({ !$0.removing }).sorted(by: { $0.x < $1.x }).enumerated() { cat.slot = i }
    }

    func next(_ cat: Cat) {
        if extraNext(cat) { return }
        let b = cat.breed
        if cat.mode == .loaf {
            cat.setMode(.stretch, 1.1)
            return
        }
        if cat.mode == .stretch && Bool.random() {
            cat.setMode(.yawn, 0.9)
            return
        }
        let others = cats.filter { $0 !== cat && $0.mode != .loaf && !$0.removing && $0.mode != .exit }
        let options: [(CatMode, CGFloat)] = [
            (.walk, 3), (.sit, 2.5), (.groom, 1.4),
            (.loaf, b.sleepy * (isNight ? 9 : 1.6)),
            (.run, b.playful * 0.5 * (isNight ? 0.1 : 1)),
            (.boopGo, others.isEmpty ? 0 : 0.9),
        ]
        var s = options.reduce(0) { $0 + $1.1 } * rnd(0, 1)
        var pick = CatMode.sit
        for (mode, weight) in options {
            s -= weight
            if s <= 0 {
                pick = mode
                break
            }
        }
        switch pick {
        case .walk:
            cat.tx = clamp(cat.x + rnd(40, 170) * (Bool.random() ? 1 : -1), 14, width - 14)
            cat.setMode(.walk, 99)
        case .run:
            cat.tx = clamp(rnd(0, width), 14, width - 14)
            cat.setMode(.run, 99)
        case .groom:
            cat.setMode(.groom, rnd(2.5, 5))
        case .loaf:
            cat.setMode(.loaf, rnd(9, 22) * (isNight ? 2 : 1))
        case .boopGo:
            cat.other = others.randomElement()
            cat.setMode(.boopGo, 99)
        default:
            cat.setMode(.sit, rnd(2, 6))
        }
    }

    private func update(_ dt: CGFloat) {
        t += dt
        dark += ((isNight ? 0.62 : 0) - dark) * min(1, dt * 2)
        let now = CACurrentMediaTime()
        let tapList = taps
        taps.removeAll()
        let doubles = doubleTaps
        doubleTaps.removeAll()
        let points = Array(touches.values)

        if t >= powerCheckAt {
            powerCheckAt = t + 20
            onBattery = CatScene.isOnBattery()
        }
        if let at = saveAt, t >= at { save() }
        if t >= trustCheckAt {
            trustCheckAt = t + 2
            checkKeyboardAccess()
        }

        let due = pending.filter { $0.at <= t }
        pending.removeAll { $0.at <= t }
        due.forEach { $0.run() }

        if t - lastKs > 4 && ksTarget > 0 { ksTarget = max(0, ksTarget - dt * 0.3) }

        for x in doubles {
            if let ball = ball, !ball.held, abs(ball.x - x) < 9 {
                fetchBall()
            } else if !cats.contains(where: { abs($0.x - x) < ($0.mode == .front ? 14 * frontScale($0) : 13) }) {
                dropBall(at: x)
            }
        }

        updateBall(dt)
        updateFlies(dt)
        updateExtras(dt, points: points)

        let fastest = points.max(by: { abs(recentVx($0, now)) < abs(recentVx($1, now)) })
        let favorite = roster.max(by: { $0.affection < $1.affection }).flatMap { $0.affection > 8 ? $0 : nil }

        for cat in cats {
            updateCat(cat, dt, now: now, taps: tapList, points: points, fastest: fastest, favorite: favorite)
        }
        cats.removeAll { $0.removing && $0.mode == .exit && ($0.x < -20 || $0.x > width + 20) }
        if !deletedIds.isEmpty {
            let onScreen = cats
            let gone = roster.filter { cat in deletedIds.contains(cat.breed.key) && !onScreen.contains(where: { $0 === cat }) }
            roster.removeAll { cat in gone.contains(where: { $0 === cat }) }
            gone.forEach { deletedIds.remove($0.breed.key) }
        }

        if let completion = exitCompletion,
           t > exitDeadline || cats.allSatisfy({ $0.x < -20 || $0.x > width + 20 }) {
            exitCompletion = nil
            paused = true
            completion()
        }

        // sitting cats don't stack on top of each other
        let resting: [CatMode] = [.sit, .loaf, .groom]
        for i in 0 ..< cats.count {
            for j in (i + 1) ..< max(i + 1, cats.count) {
                let a = cats[i], b = cats[j]
                if resting.contains(a.mode) && resting.contains(b.mode) && abs(a.x - b.x) < 9 {
                    let s: CGFloat = a.x < b.x ? -1 : 1
                    a.x = clamp(a.x + s * dt * 6, 12, width - 12)
                    b.x = clamp(b.x - s * dt * 6, 12, width - 12)
                }
            }
        }

        flies.removeAll { !$0.alive }
        sparks = sparks.compactMap { s in
            var s = s
            s.life -= dt * 1.6
            s.x += s.vx * dt
            s.y += s.vy * dt
            s.vy += 30 * dt
            return s.life > 0 ? s : nil
        }
        dust = dust.compactMap { d in
            var d = d
            d.life -= dt * 2.2
            d.x += d.vx * dt
            d.y += d.vy * dt
            d.vx *= 0.92
            return d.life > 0 ? d : nil
        }
        effects = effects.compactMap { e in
            var e = e
            e.life -= dt * (e.kind == .z ? 0.45 : 0.8)
            e.y -= dt * (e.kind == .bang ? 2 : 6)
            return e.life > 0 ? e : nil
        }
        for b in bubbles { b.life -= dt }
        bubbles.removeAll { $0.life <= 0 }
    }

    private func updateBall(_ dt: CGFloat) {
        guard let ball = ball, !ball.held else { return }
        if ball.y < ballGroundY {
            ball.vy += 90 * dt
        }
        ball.y += ball.vy * dt
        if ball.y >= ballGroundY {
            ball.y = ballGroundY
            ball.vy = ball.vy > 20 ? -ball.vy * 0.4 : 0
            ball.vx *= exp(-1.1 * dt)
        }
        ball.x += ball.vx * dt
        ball.rot += ball.vx * dt / 3
        if ball.x < 4 {
            ball.x = 4
            ball.vx = abs(ball.vx) * 0.7
        }
        if ball.x > width - 4 {
            ball.x = width - 4
            ball.vx = -abs(ball.vx) * 0.7
        }
    }

    private func updateFlies(_ dt: CGFloat) {
        for f in flies {
            f.t += dt
            switch f.state {
            case .rise:
                let k = min(1, f.t / 0.32)
                let e = 1 - pow(1 - k, 3)
                f.y = height + 6 + (f.ty - (height + 6)) * e
                f.a = 1
                if k >= 1 { f.state = .hover }
            case .hover:
                f.x += (f.vx + sin(t * 2 + f.phase) * 6) * dt
                f.y = f.ty + sin(t * 3 + f.phase) * 1.5 - (f.t > f.life - 0.45 ? (f.t - (f.life - 0.45)) * 16 : 0)
                f.a = (0.65 + 0.35 * sin(t * 9 + f.phase)) * clamp((f.life - f.t) / 0.45, 0, 1)
                if f.t > f.life { f.alive = false }
            case .drop:
                f.dropT += dt
                f.y += (floorY - f.y) * min(1, dt * 9)
                f.a = 0.15
                if (f.swatter == nil && f.dropT > 0.6) || f.dropT > 5 {
                    f.state = .fall
                    f.vy = 0
                }
            case .knocked:
                f.x += f.vx * dt
                f.y += f.vy * dt
                f.vy += 70 * dt
                f.rot += f.spin * dt
                if f.y > floorY && f.vy > 0 {
                    f.y = floorY
                    f.vy *= -0.45
                    f.vx *= 0.7
                    f.spin *= 0.6
                }
                if f.x < -10 || f.x > width + 10 { f.alive = false }
                f.knockT += dt
                if f.knockT > 2.2 { f.state = .fall }
            case .fall:
                f.vy += 50 * dt
                f.y += f.vy * dt
                f.a = 0.1
                if f.y > height + 8 { f.alive = false }
            }
        }
    }

    func frontScale(_ cat: Cat) -> CGFloat {
        var s = 0.68 + cat.cl * 0.87
        if cat.cl > 0.85 { s *= 1 + sin(t * 2.4 + CGFloat(cat.seed)) * 0.025 + 0.015 }
        if cat.boopT > 0 { s *= 1 + 0.07 * sin(cat.boopT / 0.35 * .pi) }
        return s * sqrt(cat.breed.size)
    }

    private func updateCat(_ cat: Cat, _ dt: CGFloat, now: CFTimeInterval, taps: [CGFloat], points: [TouchPoint],
                           fastest: TouchPoint?, favorite: Cat?) {
        cat.mt += dt
        cat.look = max(0, cat.look - dt)
        cat.disturb = max(0, cat.disturb - dt * 0.5)
        cat.land = max(0, cat.land - dt)
        cat.boopT = max(0, cat.boopT - dt)
        cat.meowT = max(0, cat.meowT - dt)
        cat.earT -= dt
        if cat.earT < -2 && rnd(0, 1) < dt * 0.4 { cat.earT = 0.22 }

        let front = cat.mode == .front
        let reach: CGFloat = front ? 14 * frontScale(cat) : 11
        let leaving = cat.mode == .exit || cat.mode == .enter

        // taps
        if !leaving, let tapX = taps.first(where: { abs($0 - cat.x) < reach + 2 }) {
            if cat.isExtraMode {
                tapExtra(cat)
            } else if front {
                cat.boopT = 0.35
                cat.happy = 0.8
                spawn(.heart, cat.x - 2, 2)
                if rnd(0, 1) < 0.4 { cat.meowT = 0.5 }
            } else if cat.mode == .loaf {
                spawn(.bang, cat.x + cat.dir * 6, 9)
                cat.setMode(.stretch, 1.2)
                cat.happy = 0
            } else if cat.breed.playful > 0.55 && ![.jump, .hunt, .swatGo, .swat, .attend, .carry, .fetch].contains(cat.mode) {
                cat.tx = tapX
                cat.prey = nil
                cat.setMode(.crouch, 0.35)
            } else if ![.jump, .attend, .carry].contains(cat.mode) {
                spawn(.heart, cat.x + cat.dir * 5, 8)
                cat.setMode(.sit, 2.5)
            }
        }

        // petting: a slow finger over the cat
        let petted = !leaving && points.contains { abs($0.x - cat.x) < reach && abs(recentVx($0, now)) < 70 }
        if petted && ![.jump, .crouch, .hunt, .swatGo, .swat, .attend, .carry, .fetch].contains(cat.mode) {
            cat.petT += dt
            cat.petIdle = 0
        } else {
            cat.petT = max(0, cat.petT - dt * 2)
            cat.petIdle += dt
            if cat.petIdle > 3 { cat.nameShown = false }
        }
        if cat.petT > 0.35 {
            cat.happy = 1.2
            cat.affection += dt
            saveSoon()
            if !cat.nameShown {
                cat.nameShown = true
                if !front { bubbles.append(Bubble(cat: cat, text: cat.breed.displayName)) }
            }
            if ![.loaf, .sit, .front].contains(cat.mode) && !cat.isExtraMode { cat.setMode(.sit, 3) }
            cat.dur = max(cat.dur, cat.mt + 1.5)
            cat.heartT -= dt
            if cat.heartT <= 0 {
                let hx = front ? cat.x + rnd(-8, 8) : cat.x + cat.dir * (cat.mode == .loaf ? 7 : 4) + rnd(-2, 2)
                spawn(.heart, hx, front ? 2 : (cat.mode == .loaf ? 11 : 6))
                cat.heartT = 0.5
            }
        } else {
            cat.happy = max(0, cat.happy - dt)
        }

        // a fast swipe: playful cats give chase
        if let f = fastest, abs(recentVx(f, now)) > 150, cat.breed.playful > 0.45, abs(f.x - cat.x) < 230, cat.happy <= 0,
           [.sit, .walk, .groom, .run, .boop].contains(cat.mode), ksTarget == 0 {
            cat.setMode(.chase, 99)
        }
        // the yarn ball rolling by
        if let ball = ball, !ball.held, abs(ball.vx) > 14, cat.breed.playful > 0.5, abs(ball.x - cat.x) < 260,
           [.walk, .sit, .groom].contains(cat.mode), rnd(0, 1) < dt * 2 {
            cat.setMode(.ballChase, 99)
        }
        // the favorite cat comes to a resting finger
        if let fav = favorite, fav === cat, [.sit, .walk, .groom].contains(cat.mode),
           let p = points.first(where: { now - $0.start > 1 && abs(recentVx($0, now)) < 25 }),
           abs(p.x - cat.x) > 25, rnd(0, 1) < dt * 0.6 {
            cat.tx = p.x - (p.x > cat.x ? 10 : -10)
            cat.setMode(.come, 99)
        }
        // look at the finger
        if [.sit, .groom].contains(cat.mode), let p = points.min(by: { abs($0.x - cat.x) < abs($1.x - cat.x) }),
           abs(p.x - cat.x) < 70, abs(p.x - cat.x) > 4 {
            cat.dir = p.x > cat.x ? 1 : -1
        }

        switch cat.mode {
        case .walk:
            if moveTo(cat, cat.tx, 15, dt) { next(cat) }
        case .run:
            if moveTo(cat, cat.tx, 58, dt) { cat.setMode(.sit, rnd(1.5, 3)) }
        case .enter:
            if moveTo(cat, cat.tx, 55, dt) { cat.setMode(.sit, rnd(1, 3)) }
        case .exit:
            moveTo(cat, cat.tx, 95, dt)
        case .come:
            if moveTo(cat, cat.tx, 50, dt) {
                cat.setMode(.sit, 3)
                cat.happy = 1
                spawn(.heart, cat.x - 2, 6)
            }
        case .chase:
            guard let f = fastest, now - f.lastMove < 0.9 else {
                cat.setMode(.sit, 2)
                break
            }
            if abs(f.x - cat.x) < 22 {
                cat.tx = f.x
                cat.prey = nil
                cat.setMode(.crouch, 0.45)
            } else {
                moveTo(cat, f.x, 72, dt)
            }
        case .attend:
            if ksTarget == 0 {
                cat.setMode(.sit, 1.5)
            } else if moveTo(cat, slotX(cat), 150, dt) {
                cat.cl = 0
                cat.setMode(.front, 99)
            }
        case .front:
            cat.cl += (ksTarget - cat.cl) * min(1, dt * 2.4)
            cat.x += (slotX(cat) - cat.x) * min(1, dt * 3)
            cat.pawT = max(0, cat.pawT - dt)
            cat.pawCool -= dt
            if cat.cl > 0.85 && cat.pawCool <= 0 && cat.pawT <= 0 && rnd(0, 1) < dt * 0.6 {
                cat.pawT = 1.1
                cat.pawCool = rnd(2, 4)
            }
            if cat.cl > 0.7 && rnd(0, 1) < dt * 0.08 { cat.meowT = 0.45 }
            if ksTarget == 0 && cat.cl < 0.04 {
                cat.cl = 0
                cat.pawT = 0
                cat.setMode(.sit, rnd(1, 2.5))
            }
        case .hunt:
            guard let f = cat.prey, f.alive, f.isLit, ksTarget == 0 else {
                cat.prey = nil
                cat.setMode(.sit, 1.2)
                break
            }
            let lead = f.x + f.vx * 0.35
            if abs(lead - cat.x) < 9 && f.t > 0.2 {
                cat.tx = lead
                cat.setMode(.crouch, 0.22)
            } else {
                moveTo(cat, lead, 80, dt)
            }
        case .swatGo:
            guard let f = cat.target, f.alive, f.state == .drop else {
                cat.target = nil
                cat.setMode(.sit, 1)
                break
            }
            let side: CGFloat = f.x >= cat.x ? 1 : -1
            if moveTo(cat, f.x - side * 10, 68, dt) {
                cat.dir = side
                cat.setMode(.swat, 0.6)
            }
        case .swat:
            if !cat.done && cat.mt >= 0.15, let f = cat.target, f.alive, f.state == .drop {
                cat.done = true
                f.state = .knocked
                f.vx = cat.dir * rnd(85, 125)
                f.vy = -rnd(22, 34)
                f.spin = cat.dir * rnd(9, 14)
                puff(f.x)
            }
            if cat.mt >= cat.dur {
                cat.target = nil
                cat.happy = 0.7
                cat.setMode(.sit, 1.6)
            }
        case .boopGo:
            guard let o = cat.other, cats.contains(where: { $0 === o }), o.mode != .loaf, o.mode != .exit else {
                cat.setMode(.sit, 2)
                break
            }
            let side: CGFloat = o.x > cat.x ? -1 : 1
            if moveTo(cat, o.x + side * 13, 16, dt) {
                cat.dir = -side
                o.dir = side
                cat.setMode(.boop, 2.2)
                if [.sit, .walk, .groom, .loaf].contains(o.mode) { o.setMode(.boop, 2.2) }
                spawn(.heart, (cat.x + o.x) / 2 - 2, 4)
            }
        case .ballChase:
            guard let ball = ball, !ball.held else {
                next(cat)
                break
            }
            if abs(ball.x - cat.x) < 6 && ball.y >= ballGroundY - 1 {
                ball.vx = (ball.x >= cat.x ? 1 : -1) * rnd(60, 130)
                ball.vy = -rnd(10, 25)
                if Bool.random() {
                    cat.tx = ball.x + (ball.vx > 0 ? 30 : -30)
                    cat.setMode(.crouch, 0.4)
                } else {
                    cat.setMode(.sit, 1.2)
                }
            } else {
                moveTo(cat, ball.x, 64, dt)
            }
        case .fetch:
            guard let ball = ball, !ball.held else {
                cat.setMode(.sit, 1)
                break
            }
            if moveTo(cat, ball.x, 70, dt) || abs(ball.x - cat.x) < 4 {
                ball.held = true
                cat.carrying = true
                cat.tx = cat.x < width / 2 ? -24 : width + 24
                cat.setMode(.carry, 99)
            }
        case .carry:
            if moveTo(cat, cat.tx, 60, dt) {
                cat.carrying = false
                ball = nil
                cat.tx = rnd(30, max(31, width - 30))
                cat.setMode(.enter, 99)
            }
        case .crouch:
            if cat.mt >= cat.dur {
                var tx = cat.tx
                if let p = cat.prey, p.alive { tx = p.x + p.vx * 0.25 }
                if cat.prey == nil && abs(tx - cat.x) < 20 { tx = cat.x + cat.dir * 30 }
                cat.jump = Jump(from: cat.x, to: clamp(tx, 10, width - 10), t: 0, h: cat.prey != nil ? 12 : 9)
                if let j = cat.jump, j.to != cat.x { cat.dir = j.to > cat.x ? 1 : -1 }
                cat.setMode(.jump, 0.5)
            }
        case .jump:
            guard var j = cat.jump else {
                cat.setMode(.sit, 1)
                break
            }
            j.t += dt / 0.5
            cat.jump = j
            let k = min(1, j.t)
            cat.x = j.from + (j.to - j.from) * k
            cat.jy = sin(k * .pi) * j.h
            if let f = cat.prey, f.alive, f.state == .hover, k > 0.3, k < 0.75 {
                let hx = cat.x + cat.dir * 6, hy = ground - CGFloat(sideH) + 5 - cat.jy
                if abs(f.x - hx) < 7 && abs(f.y - hy) < 8 {
                    f.alive = false
                    burst(f.x, f.y)
                    cat.caught = true
                }
            }
            if k >= 1 {
                cat.jy = 0
                cat.land = 0.18
                puff(cat.x)
                cat.prey = nil
                if let ball = ball, !ball.held, abs(ball.x - cat.x) < 8 { ball.vx += cat.dir * 120 }
                if cat.caught {
                    cat.caught = false
                    cat.happy = 1
                    countCatch()
                    CatSounds.shared.play(.mrrp, pan: pan(cat.x))
                    cat.setMode(.munch, 1.1)
                    spawn(.heart, cat.x + cat.dir * 4, 5)
                } else {
                    cat.setMode(.sit, rnd(0.8, 1.8))
                }
            }
        case .eatGo, .eat, .wave, .sulk, .boxGo, .inBox, .pomodoro, .warmGo, .warm, .laserChase, .mouseHunt:
            updateExtraMode(cat, dt)
        default:
            if cat.mode == .loaf {
                cat.zT -= dt
                if cat.zT <= 0 && cat.happy <= 0 {
                    spawn(.z, cat.x + cat.dir * 9, 8)
                    cat.zT = 1.6
                }
            }
            if cat.mt >= cat.dur && cat.petT <= 0.35 { next(cat) }
        }
    }

    // MARK: - Memory

    private func countCatch() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "cats.caught.day") != CatScene.dayString() { caughtToday = 0 }
        caughtToday += 1
        extras.stats.caught(today: caughtToday)
        saveSoon()
    }

    private func saveSoon() {
        if saveAt == nil { saveAt = t + 5 }
    }

    func save() {
        saveAt = nil
        extras.stats.save()
        let defaults = UserDefaults.standard
        defaults.set(cats.filter { !$0.removing }.map { $0.breed.key }, forKey: "cats.enabledIds")
        var affection: [String: Double] = [:]
        for cat in roster where !deletedIds.contains(cat.breed.key) { affection[cat.breed.key] = Double(cat.affection) }
        defaults.set(affection, forKey: "cats.affectionById")
        defaults.set(CatScene.dayString(), forKey: "cats.caught.day")
        defaults.set(caughtToday, forKey: "cats.caught.count")
    }

    var caughtTodayNow: Int {
        return UserDefaults.standard.string(forKey: "cats.caught.day") == CatScene.dayString() || saveAt != nil ? caughtToday : 0
    }

    private static func dayString() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPMBatteryPowerKey
    }
}

