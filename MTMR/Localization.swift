//
//  Localization.swift
//  MTMR
//
//  Russian / English for the menu and the cats. "System" follows the macOS language.
//

import Foundation

enum AppLanguage: String {
    case system = ""
    case ru
    case en
}

var isRussian: Bool {
    switch AppLanguage(rawValue: AppSettings.language) ?? .system {
    case .ru: return true
    case .en: return false
    case .system: return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    }
}

/// Picks the string for the current language
func tr(_ russian: String, _ english: String) -> String {
    return isRussian ? russian : english
}

/// The Russian word for a count: 1 буква, 2 буквы, 5 букв, 21 буква
func ruCount(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n10 = abs(n) % 10, n100 = abs(n) % 100
    if n10 == 1 && n100 != 11 { return one }
    if (2 ... 4).contains(n10) && !(12 ... 14).contains(n100) { return few }
    return many
}

/// Standard buttons and panels (Open, Cancel, Delete) follow the app's language from the next launch
func applyAppLanguage() {
    switch AppLanguage(rawValue: AppSettings.language) ?? .system {
    case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    case .ru: UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
    case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
    }
}
