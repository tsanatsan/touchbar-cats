//
//  CatBreeds.swift
//  MTMR
//
//  Ten pixel cats for the Touch Bar: colors, body shapes and temper.
//

import AppKit

struct RGB {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF)
        g = CGFloat((hex >> 8) & 0xFF)
        b = CGFloat(hex & 0xFF)
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(_ other: RGB, _ k: CGFloat) -> RGB {
        return RGB(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k)
    }
}

enum Paint: Int, CaseIterable {
    case outline, fur, dark, belly, eye, eye2, pink, patch
    case white, whisker, pupil, yarnA, yarnB, hatRed, hatWhite
}

enum Part {
    case body, belly, head, ear, earIn, tuft, eye, eyeClosed, nose, mouth, muzzle, chest
    case leg, paw, bean, tail, tailTip, whisker, blush, shine, pupil, yarn, ruff, tuftIn, hat
}

enum Coat: String, CaseIterable {
    case tabby // stripes
    case solid
    case tuxedo // white chest and paws
    case calico // white with orange and black patches
    case points // siamese: dark ears, mask, paws and tail
    case bicolor // white muzzle blaze, chest and paws
    case skin // hairless sphynx: wrinkles instead of fur pattern
}

enum EyeShape: String, CaseIterable {
    case round, big, almond
}

enum EarShape: String, CaseIterable {
    case normal, big, folded, tufted
}

enum TailShape: String, CaseIterable {
    case normal, bushy, thin
}

struct Breed {
    let name: String
    let kind: String
    let coat: Coat
    let palette: [Paint: RGB]
    let playful: CGFloat
    let sleepy: CGFloat
    var size: CGFloat = 1
    var fat = false
    var ears = EarShape.normal
    var tail = TailShape.normal
    var speed: CGFloat = 1
    var eyes = EyeShape.round
    var lids = false // sleepy half-closed eyelids until excited
    var ruff = false // fluffy collar around the face
    var id = "" // stable key for settings; built-in cats use their name
    var custom = false // made in the cat workshop from a photo
    var kitten = false // small, follows its parent around
    var parent: String? = nil

    var key: String { return id.isEmpty ? name : id }

    func color(_ paint: Paint) -> RGB {
        if let c = palette[paint] { return c }
        switch paint {
        case .white: return RGB(0xFFFFFF)
        case .whisker: return RGB(0xB9B4AC)
        case .pupil: return RGB(0x141418)
        case .yarnA: return RGB(0xF27A98)
        case .yarnB: return RGB(0xC84468)
        case .hatRed: return RGB(0xD8343C)
        case .hatWhite: return RGB(0xF6F2EC)
        case .eye2: return palette[.eye] ?? RGB(0xFFFFFF)
        default: return palette[.fur] ?? RGB(0xFFFFFF)
        }
    }
}

private func palette(o: UInt32, f: UInt32, d: UInt32, b: UInt32, e: UInt32, p: UInt32,
                     patch: UInt32? = nil, e2: UInt32? = nil) -> [Paint: RGB] {
    var result: [Paint: RGB] = [.outline: RGB(o), .fur: RGB(f), .dark: RGB(d), .belly: RGB(b), .eye: RGB(e), .pink: RGB(p)]
    if let patch = patch { result[.patch] = RGB(patch) }
    if let e2 = e2 { result[.eye2] = RGB(e2) }
    return result
}

/// Ten built-in cats plus up to eight cats made from photos
let maxCats = 18

let catBreeds: [Breed] = [
    Breed(name: "Рыжик", kind: "рыжий полосатый", coat: .tabby,
          palette: palette(o: 0x4A2A14, f: 0xE8964A, d: 0xB05F26, b: 0xF7D6AE, e: 0x9BE26F, p: 0xFF9AA8),
          playful: 0.9, sleepy: 0.3),
    Breed(name: "Уголёк", kind: "чёрный", coat: .solid,
          palette: palette(o: 0x7A7A94, f: 0x2F2F3A, d: 0x1D1D25, b: 0x454552, e: 0xF5D33F, p: 0xD7798A),
          playful: 0.6, sleepy: 0.6, eyes: .big),
    Breed(name: "Фрак", kind: "смокинг", coat: .tuxedo,
          palette: palette(o: 0x70708A, f: 0x363642, d: 0x24242C, b: 0xF2F2EE, e: 0x9BE07A, p: 0xFF9AA8),
          playful: 0.7, sleepy: 0.5),
    Breed(name: "Ириска", kind: "трёхцветная толстушка", coat: .calico,
          palette: palette(o: 0x5A4A3C, f: 0xF3EEE4, d: 0xDE8A3C, b: 0xFFFAF2, e: 0xE0B040, p: 0xFF9AA8, patch: 0x3A3530),
          playful: 0.4, sleepy: 0.9, fat: true, speed: 0.75),
    Breed(name: "Сима", kind: "сиамская", coat: .points,
          palette: palette(o: 0x4A3326, f: 0xF0E4CF, d: 0x5E4334, b: 0xF8F0E2, e: 0x5FB4FF, p: 0xE88A96),
          playful: 0.8, sleepy: 0.4, eyes: .almond),
    Breed(name: "Пончик", kind: "толстый серо-белый", coat: .bicolor,
          palette: palette(o: 0x3E4250, f: 0x8C93A3, d: 0x6B7282, b: 0xF4F4F2, e: 0xF2C14E, p: 0xFFA0B0),
          playful: 0.3, sleepy: 0.95, size: 1.05, fat: true, speed: 0.7, lids: true),
    Breed(name: "Добби", kind: "сфинкс", coat: .skin,
          palette: palette(o: 0x6E4A44, f: 0xE9C2B0, d: 0xC4917F, b: 0xF3D6C8, e: 0x7FD3C4, p: 0xE58A96),
          playful: 0.75, sleepy: 0.5, ears: .big, tail: .thin, eyes: .big),
    Breed(name: "Барон", kind: "мейн-кун", coat: .tabby,
          palette: palette(o: 0x2E2216, f: 0x8A6A48, d: 0x4E3A26, b: 0xE6D6BE, e: 0xD9B23A, p: 0xD99A9A),
          playful: 0.55, sleepy: 0.5, size: 1.18, ears: .tufted, tail: .bushy, speed: 1.1, ruff: true),
    Breed(name: "Пуговка", kind: "вислоухая", coat: .solid,
          palette: palette(o: 0x34404C, f: 0xA7B4C2, d: 0x7F8C9A, b: 0xDDE4EA, e: 0xE8A33A, p: 0xF0A0B0),
          playful: 0.65, sleepy: 0.6, size: 0.92, ears: .folded, eyes: .big),
    Breed(name: "Снежок", kind: "белый, глаза разные", coat: .solid,
          palette: palette(o: 0x8A8A96, f: 0xF7F7F4, d: 0xDCDCD6, b: 0xFFFFFF, e: 0x6CB6FF, p: 0xFFAAB8, e2: 0xF2B33A),
          playful: 0.5, sleepy: 0.7, tail: .bushy, eyes: .big, ruff: true),
]

private let englishNames = [
    "Рыжик": "Ginger", "Уголёк": "Coal", "Фрак": "Tux", "Ириска": "Toffee", "Сима": "Sima",
    "Пончик": "Donut", "Добби": "Dobby", "Барон": "Baron", "Пуговка": "Button", "Снежок": "Snowball",
]
private let englishKinds = [
    "Рыжик": "ginger tabby", "Уголёк": "black", "Фрак": "tuxedo", "Ириска": "chubby calico", "Сима": "Siamese",
    "Пончик": "chubby grey-and-white", "Добби": "Sphynx", "Барон": "Maine Coon", "Пуговка": "Scottish Fold",
    "Снежок": "white, odd-eyed",
]

extension Breed {
    var displayName: String { return tr(name, englishNames[name] ?? name) }
    var displayKind: String { return tr(kind, englishKinds[name] ?? kind) }
}

extension RGB {
    var hex: UInt32 {
        return UInt32(max(0, min(255, r.rounded()))) << 16 | UInt32(max(0, min(255, g.rounded()))) << 8 | UInt32(max(0, min(255, b.rounded())))
    }

    var luminance: CGFloat { return (0.299 * r + 0.587 * g + 0.114 * b) / 255 }
}

extension Coat {
    var title: String {
        switch self {
        case .tabby: return tr("полосатый", "tabby")
        case .solid: return tr("однотонный", "solid")
        case .tuxedo: return tr("смокинг", "tuxedo")
        case .calico: return tr("трёхцветный", "calico")
        case .points: return tr("сиамский", "colorpoint")
        case .bicolor: return tr("с белым", "bicolor")
        case .skin: return tr("лысый", "hairless")
        }
    }
}

extension EarShape {
    var title: String {
        switch self {
        case .normal: return tr("обычные", "normal")
        case .big: return tr("большие", "big")
        case .folded: return tr("вислые", "folded")
        case .tufted: return tr("с кисточками", "tufted")
        }
    }
}

extension TailShape {
    var title: String {
        switch self {
        case .normal: return tr("обычный", "normal")
        case .bushy: return tr("пушистый", "bushy")
        case .thin: return tr("тонкий", "thin")
        }
    }
}

extension EyeShape {
    var title: String {
        switch self {
        case .round: return tr("круглые", "round")
        case .big: return tr("большие", "big")
        case .almond: return tr("миндалевидные", "almond")
        }
    }
}

// MARK: - Cats made from photos

struct CustomCat: Codable {
    var id: String
    var name: String
    var coat: String
    var ears: String
    var tail: String
    var eyes: String
    var fat: Bool
    var ruff: Bool
    var colors: [String: UInt32] // fur, dark, belly, patch, eye, eye2, pink
    var kitten: Bool? = nil
    var parent: String? = nil

    var breed: Breed {
        func c(_ key: String, _ fallback: UInt32) -> UInt32 { return colors[key] ?? fallback }
        let fur = RGB(c("fur", 0x999999))
        let dark = RGB(c("dark", fur.mixed(RGB(0x000000), 0.4).hex))
        // dark cats get a light rim so they stay visible on the black Touch Bar
        let outline = fur.luminance < 0.22 ? fur.mixed(RGB(0xFFFFFF), 0.38) : dark.mixed(RGB(0x000000), 0.5)
        var palette: [Paint: RGB] = [
            .outline: outline, .fur: fur, .dark: dark,
            .belly: RGB(c("belly", fur.mixed(RGB(0xFFFFFF), 0.5).hex)),
            .eye: RGB(c("eye", 0xE0B040)), .pink: RGB(c("pink", 0xFF9AA8)),
        ]
        if let patch = colors["patch"] { palette[.patch] = RGB(patch) }
        if let eye2 = colors["eye2"] { palette[.eye2] = RGB(eye2) }
        let coat = Coat(rawValue: self.coat) ?? .solid
        let small = kitten ?? false
        return Breed(name: name, kind: small ? tr("котёнок", "kitten") : coat.title, coat: coat, palette: palette,
                     playful: small ? 0.95 : 0.7, sleepy: fat ? 0.8 : (small ? 0.6 : 0.5),
                     size: small ? 0.62 : (fat ? 1.05 : 1), fat: fat, ears: EarShape(rawValue: ears) ?? .normal,
                     tail: TailShape(rawValue: tail) ?? .normal, speed: small ? 1.15 : (fat ? 0.8 : 1),
                     eyes: EyeShape(rawValue: eyes) ?? .round, ruff: ruff, id: id, custom: true, kitten: small, parent: parent)
    }

    /// The same cat as a record: used for kittens and for sharing cats as files
    init(breed: Breed, id: String = "custom-" + UUID().uuidString) {
        self.id = id
        name = breed.displayName
        coat = breed.coat.rawValue
        ears = breed.ears.rawValue
        tail = breed.tail.rawValue
        eyes = breed.eyes.rawValue
        fat = breed.fat
        ruff = breed.ruff
        var colors: [String: UInt32] = [:]
        let keys: [(String, Paint)] = [("fur", .fur), ("dark", .dark), ("belly", .belly), ("eye", .eye), ("pink", .pink)]
        for (key, paint) in keys { colors[key] = breed.color(paint).hex }
        if breed.palette[.patch] != nil { colors["patch"] = breed.color(.patch).hex }
        if breed.palette[.eye2] != nil { colors["eye2"] = breed.color(.eye2).hex }
        self.colors = colors
        kitten = breed.kitten ? true : nil
        parent = breed.parent
    }

    init(id: String, name: String, coat: String, ears: String, tail: String, eyes: String, fat: Bool, ruff: Bool,
         colors: [String: UInt32], kitten: Bool? = nil, parent: String? = nil) {
        self.id = id
        self.name = name
        self.coat = coat
        self.ears = ears
        self.tail = tail
        self.eyes = eyes
        self.fat = fat
        self.ruff = ruff
        self.colors = colors
        self.kitten = kitten
        self.parent = parent
    }

    /// A kitten that looks like its parent and follows it around
    static func kitten(of parent: Breed) -> CustomCat {
        var record = CustomCat(breed: parent)
        record.name = tr("Котёнок", "Kitten") + " " + parent.displayName
        record.kitten = true
        record.fat = false
        record.parent = parent.key
        return record
    }
}

enum CustomCatStore {
    private static let key = "cats.custom"

    static func load() -> [CustomCat] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CustomCat].self, from: data)) ?? []
    }

    static func save(_ cats: [CustomCat]) {
        if let data = try? JSONEncoder().encode(cats) { UserDefaults.standard.set(data, forKey: key) }
    }
}
