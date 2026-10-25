//
//  CatWorkshop.swift
//  MTMR
//
//  "Cat workshop" window: drop a photo of your cat, get a pixel twin, tweak it, move it onto the Touch Bar.
//

import AppKit

final class CatWorkshop: NSObject, NSWindowDelegate {
    static let shared = CatWorkshop()

    private var window: NSWindow?
    private var record = CatWorkshop.blankRecord()
    private let photo = DropImageView()
    private let status = NSTextField(labelWithString: "")
    private let preview = CatPreviewView()
    private let name = NSTextField(string: "")
    private let coat = NSPopUpButton()
    private let ears = NSPopUpButton()
    private let tail = NSPopUpButton()
    private let eyes = NSPopUpButton()
    private let fat = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let ruff = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let colorKeys = ["fur", "dark", "belly", "patch", "eye", "eye2", "pink"]
    private var wells: [String: NSColorWell] = [:]
    private let settle = NSButton(title: "", target: nil, action: nil)

    private static func blankRecord() -> CustomCat {
        return CustomCat(id: "custom-" + UUID().uuidString, name: tr("Мой кот", "My cat"), coat: Coat.tabby.rawValue,
                         ears: EarShape.normal.rawValue, tail: TailShape.normal.rawValue, eyes: EyeShape.round.rawValue,
                         fat: false, ruff: false,
                         colors: ["fur": 0xB9A58C, "dark": 0x6E5A44, "belly": 0xEDE3D4, "eye": 0x9BD26F, "pink": 0xFF9AA8])
    }

    /// Without a record: a new cat. With one: one of your cats to edit
    func show(record existing: CustomCat? = nil) {
        if window == nil { build() }
        record = existing ?? CatWorkshop.blankRecord()
        photo.image = nil
        let editing = CatScene.shared.roster.contains { $0.breed.key == record.id }
        status.stringValue = existing == nil
            ? tr("Перетащите сюда фото своего кота — или выберите несколько фото сразу, так окрас угадается точнее.",
                 "Drop a photo of your cat here — or pick several photos at once for a better match.")
            : tr("Поправьте кота или перерисуйте его по другому фото.", "Tweak your cat or redraw it from another photo.")
        settle.title = editing ? tr("Сохранить", "Save") : tr("Поселить на тачбар", "Move onto the Touch Bar")
        fillControls()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 470), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = tr("Мастерская котов", "Cat workshop")
        w.isReleasedWhenClosed = false
        w.delegate = self

        photo.imageScaling = .scaleProportionallyUpOrDown
        photo.isEditable = true
        photo.wantsLayer = true
        photo.layer?.cornerRadius = 12
        photo.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        photo.target = self
        photo.action = #selector(photoChanged(_:))
        photo.translatesAutoresizingMaskIntoConstraints = false
        photo.widthAnchor.constraint(equalToConstant: 260).isActive = true
        photo.heightAnchor.constraint(equalToConstant: 260).isActive = true

        let choose = NSButton(title: tr("Выбрать фото…", "Choose photo…"), target: self, action: #selector(choosePhoto(_:)))
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        status.preferredMaxLayoutWidth = 260
        status.textColor = .secondaryLabelColor
        let left = NSStackView(views: [photo, choose, status])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 10

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 460).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 130).isActive = true

        for (popup, titles) in [(coat, Coat.allCases.map { $0.title }), (ears, EarShape.allCases.map { $0.title }),
                                (tail, TailShape.allCases.map { $0.title }), (eyes, EyeShape.allCases.map { $0.title })] {
            popup.addItems(withTitles: titles)
            popup.target = self
            popup.action = #selector(controlChanged(_:))
        }
        name.target = self
        name.action = #selector(controlChanged(_:))
        name.delegate = self
        fat.title = tr("толстый", "chubby")
        ruff.title = tr("пушистый воротник", "fluffy collar")
        for box in [fat, ruff] {
            box.target = self
            box.action = #selector(controlChanged(_:))
        }

        let colorTitles = [tr("шерсть", "fur"), tr("тёмный", "dark"), tr("светлый", "light"),
                           tr("пятна", "patches"), tr("глаз", "eye"), tr("2-й глаз", "2nd eye"), tr("нос", "nose")]
        let colorStack = NSStackView(views: zip(colorKeys, colorTitles).map { key, title in
            let well = NSColorWell()
            well.target = self
            well.action = #selector(controlChanged(_:))
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 42).isActive = true
            well.heightAnchor.constraint(equalToConstant: 26).isActive = true
            wells[key] = well
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            let column = NSStackView(views: [well, label])
            column.orientation = .vertical
            column.spacing = 3
            return column
        })
        colorStack.spacing = 8

        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.alignment = .right
            return l
        }
        let grid = NSGridView(views: [
            [label(tr("Имя", "Name")), name],
            [label(tr("Окрас", "Coat")), coat],
            [label(tr("Уши", "Ears")), ears],
            [label(tr("Хвост", "Tail")), tail],
            [label(tr("Глаза", "Eyes")), eyes],
            [label(tr("Цвета", "Colors")), colorStack],
            [NSGridCell.emptyContentView, NSStackView(views: [fat, ruff])],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        name.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let right = NSStackView(views: [preview, grid])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 14

        let body = NSStackView(views: [left, right])
        body.alignment = .top
        body.spacing = 20

        let cancel = NSButton(title: tr("Отмена", "Cancel"), target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        settle.title = tr("Поселить на тачбар", "Move onto the Touch Bar")
        settle.target = self
        settle.action = #selector(settle(_:))
        settle.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, settle])
        buttons.spacing = 10

        let root = NSStackView(views: [body, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 18
        let container = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        w.contentView = container
        window = w
    }

    // MARK: - Record <-> controls

    private func fillControls() {
        name.stringValue = record.name
        coat.selectItem(at: Coat.allCases.firstIndex(of: Coat(rawValue: record.coat) ?? .solid) ?? 0)
        ears.selectItem(at: EarShape.allCases.firstIndex(of: EarShape(rawValue: record.ears) ?? .normal) ?? 0)
        tail.selectItem(at: TailShape.allCases.firstIndex(of: TailShape(rawValue: record.tail) ?? .normal) ?? 0)
        eyes.selectItem(at: EyeShape.allCases.firstIndex(of: EyeShape(rawValue: record.eyes) ?? .round) ?? 0)
        fat.state = record.fat ? .on : .off
        ruff.state = record.ruff ? .on : .off
        let breed = record.breed
        let fallback: [String: Paint] = ["fur": .fur, "dark": .dark, "belly": .belly, "patch": .patch, "eye": .eye, "eye2": .eye2, "pink": .pink]
        for key in colorKeys {
            let c = record.colors[key].map { RGB($0) } ?? breed.color(fallback[key]!)
            wells[key]?.color = NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
        }
        settle.isEnabled = CatScene.shared.canAddCustomCat || CatScene.shared.roster.contains { $0.breed.key == record.id }
        preview.breed = breed
    }

    private func readControls() {
        record.name = name.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? tr("Мой кот", "My cat") : name.stringValue
        record.coat = Coat.allCases[max(0, coat.indexOfSelectedItem)].rawValue
        record.ears = EarShape.allCases[max(0, ears.indexOfSelectedItem)].rawValue
        record.tail = TailShape.allCases[max(0, tail.indexOfSelectedItem)].rawValue
        record.eyes = EyeShape.allCases[max(0, eyes.indexOfSelectedItem)].rawValue
        record.fat = fat.state == .on
        record.ruff = ruff.state == .on
        for key in colorKeys {
            guard let c = wells[key]?.color.usingColorSpace(.sRGB) else { continue }
            record.colors[key] = RGB(r: c.redComponent * 255, g: c.greenComponent * 255, b: c.blueComponent * 255).hex
        }
        preview.breed = record.breed
    }

    // MARK: - Actions

    @objc private func controlChanged(_: Any?) {
        readControls()
    }

    @objc private func choosePhoto(_: Any?) {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = NSImage.imageTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        load(panel.urls)
    }

    func load(_ urls: [URL]) {
        let images = urls.compactMap { NSImage(contentsOf: $0) }
        guard let first = images.first else { return }
        photo.image = first
        analyze(images)
    }

    @objc private func photoChanged(_: Any?) {
        if let image = photo.image { analyze([image]) }
    }

    private func analyze(_ images: [NSImage]) {
        status.stringValue = tr("Смотрю на кота…", "Looking at the cat…")
        let keepName = record.name
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CatWorkshop.merge(images.compactMap { CatPhotoAnalyzer.analyze($0) })
            DispatchQueue.main.async {
                guard let result = result else {
                    self.status.stringValue = tr("Не получилось разобрать фото. Попробуйте другое или настройте кота вручную.",
                                                 "Couldn't read this photo. Try another one or set the cat up by hand.")
                    return
                }
                let old = self.record
                self.record = result.record
                self.record.id = old.id
                self.record.kitten = old.kitten
                self.record.parent = old.parent
                if keepName != tr("Мой кот", "My cat") { self.record.name = keepName }
                self.fillControls()
                let coatTitle = (Coat(rawValue: result.record.coat) ?? .solid).title
                self.status.stringValue = result.foundCat
                    ? tr("Нашёл кота: окрас «\(coatTitle)». Если что-то не так — поправьте справа.",
                         "Found the cat: \(coatTitle) coat. Fix anything on the right.")
                    : tr("Кота на фото не нашёл, взял цвета из середины кадра. Проверьте справа.",
                         "Couldn't spot a cat, took colors from the middle of the photo. Check on the right.")
            }
        }
    }

    @objc private func cancel(_: Any?) {
        window?.close()
    }

    @objc private func settle(_: Any?) {
        readControls()
        if CatScene.shared.roster.contains(where: { $0.breed.key == record.id }) {
            CatScene.shared.updateCustomCat(record)
        } else {
            CatScene.shared.addCustomCat(record)
        }
        window?.close()
    }

    /// Several photos of one cat: the coat most of them agree on, colors averaged over those photos
    private static func merge(_ results: [PhotoAnalysis]) -> PhotoAnalysis? {
        guard var best = results.first else { return nil }
        guard results.count > 1 else { return best }
        let coats = Dictionary(grouping: results, by: { $0.record.coat })
        let agreeing = coats.values.max { $0.count < $1.count } ?? results
        best = agreeing[0]
        for key in ["fur", "dark", "belly", "patch", "eye", "eye2", "pink"] {
            let values = agreeing.compactMap { $0.record.colors[key] }.map { RGB($0) }
            guard !values.isEmpty, values.count * 2 >= agreeing.count else {
                best.record.colors[key] = nil
                continue
            }
            let n = CGFloat(values.count)
            best.record.colors[key] = RGB(r: values.reduce(0) { $0 + $1.r } / n, g: values.reduce(0) { $0 + $1.g } / n,
                                          b: values.reduce(0) { $0 + $1.b } / n).hex
        }
        if best.record.colors["fur"] == nil { best.record.colors["fur"] = agreeing[0].record.colors["fur"] }
        best.foundCat = results.contains { $0.foundCat }
        return best
    }

    func windowWillClose(_: Notification) {
        photo.image = nil // the photo is not kept anywhere
        preview.breed = nil
    }
}

extension CatWorkshop: NSTextFieldDelegate {
    func controlTextDidChange(_: Notification) {
        readControls()
    }
}

/// Image well that accepts dropped files and reports changes
final class DropImageView: NSImageView {}

/// Live preview: the cat walks on a strip of Touch Bar and looks out from the glass
final class CatPreviewView: NSView {
    var breed: Breed? {
        didSet {
            guard let breed = breed else {
                timer?.invalidate()
                timer = nil
                return
            }
            walker = Cat(breed: breed, index: 0)
            walker?.x = 30
            walker?.setMode(.walk, 99)
            face = Cat(breed: breed, index: 0)
            face?.setMode(.front, 99)
            face?.cl = 1
            if timer == nil {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
            needsDisplay = true
        }
    }

    private var walker: Cat?
    private var face: Cat?
    private var timer: Timer?
    private var t: CGFloat = 0
    private let pixel: CGFloat = 3

    override var isFlipped: Bool { return true }

    private func tick() {
        t += 1.0 / 30
        if let cat = walker {
            let speed: CGFloat = 14
            cat.x += cat.dir * speed / 30
            cat.frame += speed / 30 * 0.42
            if cat.x > 64 { cat.dir = -1 }
            if cat.x < 16 { cat.dir = 1 }
            cat.earT -= 1.0 / 30
            if cat.earT < -2.5 { cat.earT = 0.2 }
        }
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bg = CGPath(roundedRect: bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(bg)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.addPath(bg)
        ctx.clip()
        if let cat = walker { draw(cat, left: (cat.x - 15) * pixel, bottom: bounds.height - 10, ctx) }
        if let cat = face { draw(cat, left: bounds.width - CGFloat(frontW) * pixel - 30, bottom: bounds.height + 6, ctx, scale: pixel * 0.95) }
    }

    private func draw(_ cat: Cat, left: CGFloat, bottom: CGFloat, _ ctx: CGContext, scale: CGFloat? = nil) {
        let s = scale ?? pixel
        // the walking cat in the pack's drawing, exactly as it will look on the bar; repainted every time, the colors change while editing
        if cat.mode != .front, let pack = CatPack.shared {
            pack.forget(cat.breed.key)
            let anim = PackAnim.walk
            guard let sprite = pack.sprite(cat.breed, row: cat.dir >= 0 ? anim.right : anim.left, col: Int(cat.frame) % anim.frames) else { return }
            let n = CatPack.cell
            let top = bottom - CGFloat(sprite.bottom + 1) * s
            let x0 = left + CGFloat(15 - n / 2) * s
            for y in 0 ..< n { for x in 0 ..< n {
                guard let c = sprite.colors[y * n + x] else { continue }
                ctx.setFillColor(CGColor(colorSpace: displaySpace, components: [CGFloat(c >> 16) / 255, CGFloat((c >> 8) & 0xFF) / 255, CGFloat(c & 0xFF) / 255, 1])!)
                ctx.fill(CGRect(x: x0 + CGFloat(x) * s, y: top + CGFloat(y) * s, width: s, height: s))
            } }
            return
        }
        let (w, h, paints) = spriteScreen(cat, t: t, dark: 0)
        let top = bottom - CGFloat(h) * s
        for y in 0 ..< h {
            for x in 0 ..< w {
                guard let k = paints[y * w + x] else { continue }
                let c = cat.breed.color(k)
                ctx.setFillColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: k == .whisker ? 0.5 : 1)
                ctx.fill(CGRect(x: left + CGFloat(x) * s, y: top + CGFloat(y) * s, width: s, height: s))
            }
        }
    }
}
