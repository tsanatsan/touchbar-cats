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
