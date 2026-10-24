//
//  AppDelegate.swift
//  MTMR
//
//  Created by Anton Palgunov on 16/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var isBlockedApp: Bool = false

    private var fileSystemSource: DispatchSourceFileSystemObject?
    private var nativeTouchBarHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_: Notification) {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as NSDictionary)

        TouchBarController.shared.setupControlStripPresence()

        // ⌃⌥⌘T: swap between the MTMR bar and the system Touch Bar
        nativeTouchBarHotKey = GlobalHotKey(keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey | controlKey) { [weak self] in
            self?.toggleNativeTouchBar(nil)
        }
        if nativeTouchBarHotKey == nil {
            NSLog("MTMR: could not register ⌃⌥⌘T (taken by another app?)")
        }

        if let button = statusItem.button {
            button.image = CatIcon.image()
        }
        createMenu()

        reloadOnDefaultConfigChanged()

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_: Notification) {}

    @objc func updateIsBlockedApp() {
        if let frontmostAppId = TouchBarController.shared.frontmostApplicationIdentifier {
            isBlockedApp = AppSettings.blacklistedAppIds.firstIndex(of: frontmostAppId) != nil
        } else {
            isBlockedApp = false
        }
        createMenu()
    }

    @objc func openPreferences(_: Any?) {
        let task = Process()
        let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
        let presetPath = appSupportDirectory.appending("/items.json")
        task.launchPath = "/usr/bin/open"
        task.arguments = [presetPath]
        task.launch()
    }

    @objc func toggleControlStrip(_: Any?) {
        AppSettings.showControlStripState.toggle()
        TouchBarController.shared.resetControlStrip()
        createMenu()
    }

    @objc func toggleBlackListedApp(_: Any?) {
        if let appIdentifier = TouchBarController.shared.frontmostApplicationIdentifier {
            if let index = TouchBarController.shared.blacklistAppIdentifiers.firstIndex(of: appIdentifier) {
                TouchBarController.shared.blacklistAppIdentifiers.remove(at: index)
            } else {
                TouchBarController.shared.blacklistAppIdentifiers.append(appIdentifier)
            }
            
            AppSettings.blacklistedAppIds = TouchBarController.shared.blacklistAppIdentifiers
            TouchBarController.shared.updateActiveApp()
            updateIsBlockedApp()
        }
    }

    @objc func toggleNativeTouchBar(_: Any?) {
        TouchBarController.shared.toggleNativeTouchBar()
        createMenu()
    }

    @objc func toggleHapticFeedback(_: Any?) {
        AppSettings.hapticFeedbackState.toggle()
        createMenu()
    }

    @objc func toggleMultitouch(_: Any?) {
        AppSettings.multitouchGestures.toggle()
        TouchBarController.shared.basicView?.legacyGesturesEnabled = AppSettings.multitouchGestures
        createMenu()
    }

    @objc func toggleSeasons(_: Any?) {
        AppSettings.seasons.toggle()
        createMenu()
    }

    @objc func toggleSounds(_: Any?) {
        AppSettings.catSounds.toggle()
        if AppSettings.catSounds { CatSounds.shared.play(.mrrp, pan: 0) }
        createMenu()
    }

    @objc func toggleLaser(_: Any?) {
        AppSettings.trackpadLaser.toggle()
        CatScene.shared.syncTrackpad()
        createMenu()
    }

    @objc func setLanguage(_ item: NSMenuItem) {
        AppSettings.language = item.representedObject as? String ?? ""
        createMenu()
    }

    @objc func openPreset(_: Any?) {
        let dialog = NSOpenPanel()

        dialog.title = tr("Выберите файл items.json", "Choose an items.json file")
        dialog.showsResizeIndicator = true
        dialog.showsHiddenFiles = true
        dialog.canChooseDirectories = false
        dialog.canCreateDirectories = false
        dialog.allowsMultipleSelection = false
        dialog.allowedFileTypes = ["json"]
        dialog.directoryURL = NSURL.fileURL(withPath: NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR"), isDirectory: true)

        if dialog.runModal() == .OK, let path = dialog.url?.path {
            TouchBarController.shared.reloadPreset(path: path)
        }
    }

    @objc func toggleStartAtLogin(_: Any?) {
        LaunchAtLoginController().setLaunchAtLogin(!LaunchAtLoginController().launchAtLogin, for: NSURL.fileURL(withPath: Bundle.main.bundlePath))
        createMenu()
    }

    private func item(_ title: String, _ action: Selector?, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ id: String, items: [NSMenuItem] = []) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.identifier = NSUserInterfaceItemIdentifier(id)
        menu.delegate = self
        items.forEach { menu.addItem($0) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    func createMenu() {
        let menu = NSMenu()

        let native = item(tr("Обычный тачбар", "Regular Touch Bar"), #selector(toggleNativeTouchBar(_:)), on: AppSettings.nativeTouchBar)
        native.keyEquivalent = "t" // only shows ⌃⌥⌘T, the global hotkey does the work
        native.keyEquivalentModifierMask = [.command, .option, .control]
        menu.addItem(native)
        menu.addItem(submenu(tr("Котики", "Cats"), "cats"))

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? tr("этой программе", "this app")
        let language = AppLanguage(rawValue: AppSettings.language) ?? .system
        let languages: [NSMenuItem] = [(AppLanguage.system, tr("Как в системе", "System")), (.ru, "Русский"), (.en, "English")].map {
            let item = self.item($0.1, #selector(setLanguage(_:)), on: language == $0.0)
            item.representedObject = $0.0.rawValue
            return item
        }
        let settings = submenu(tr("Настройки", "Settings"), "settings", items: [
            item(tr("Открывать при входе", "Open at login"), #selector(toggleStartAtLogin(_:)), on: LaunchAtLoginController().launchAtLogin),
            item(tr("Тактильный отклик", "Haptic feedback"), #selector(toggleHapticFeedback(_:)), on: AppSettings.hapticFeedbackState),
            item(tr("Полоса управления справа", "Show Control Strip"), #selector(toggleControlStrip(_:)), on: AppSettings.showControlStripState),
            item(tr("Громкость двумя пальцами, яркость тремя", "Two fingers: volume, three: brightness"), #selector(toggleMultitouch(_:)), on: AppSettings.multitouchGestures),
            item(tr("Не показывать в «\(appName)»", "Hide in “\(appName)”"), #selector(toggleBlackListedApp(_:)), on: isBlockedApp),
            NSMenuItem.separator(),
            item(tr("Сезоны и праздники", "Seasons and holidays"), #selector(toggleSeasons(_:)), on: AppSettings.seasons),
            item(tr("Звуки котов", "Cat sounds"), #selector(toggleSounds(_:)), on: AppSettings.catSounds),
            item(tr("Лазер от тачпада", "Trackpad laser"), #selector(toggleLaser(_:)), on: AppSettings.trackpadLaser),
            NSMenuItem.separator(),
            item(tr("Открыть конфиг…", "Open config…"), #selector(openPreferences(_:))),
            item(tr("Загрузить пресет…", "Load preset…"), #selector(openPreset(_:))),
            NSMenuItem.separator(),
            submenu(tr("Язык", "Language"), "language", items: languages),
        ])
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: tr("Выйти", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func reloadOnDefaultConfigChanged() {
        let file = NSURL.fileURL(withPath: standardConfigPath)

        let fd = open(file.path, O_EVTONLY)

        fileSystemSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: DispatchQueue(label: "DefaultConfigChanged"))

        fileSystemSource?.setEventHandler(handler: {
            print("Config changed, reloading...")
            DispatchQueue.main.async {
                TouchBarController.shared.reloadPreset(path: file.path)
            }
        })

        fileSystemSource?.setCancelHandler(handler: {
            close(fd)
        })

        fileSystemSource?.resume()
    }
}

// MARK: - Cats menu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == "cats" else { return }
        let scene = CatScene.shared
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            menu.addItem(item(tr("Буквы выключены: разрешите «Универсальный доступ»…", "Letters are off: allow Accessibility…"),
                              #selector(openAccessibilitySettings(_:))))
            menu.addItem(NSMenuItem.separator())
        }
        let stats = scene.extras.stats
        let caughtNow = scene.caughtTodayNow
        let share = stats.typed > 0 ? Int((Double(caughtNow) / Double(stats.typed) * 100).rounded()) : 0
        for line in [
            tr("Сегодня: \(stats.typed) букв · поймано \(caughtNow) (\(share)%)", "Today: \(stats.typed) letters · \(caughtNow) caught (\(share)%)"),
            tr("Скорость: \(stats.speed) зн/мин · рекорд \(stats.bestSpeed)", "Speed: \(stats.speed) chars/min · best \(stats.bestSpeed)"),
            tr("Всего поймано: \(stats.totalCaught) · рекорд дня \(stats.bestCaught)", "Caught in total: \(stats.totalCaught) · best day \(stats.bestCaught)"),
        ] {
            let row = item(line, nil)
            row.isEnabled = false
            menu.addItem(row)
        }
        menu.addItem(NSMenuItem.separator())

        let add = item(tr("Добавить котика", "Add a cat"), #selector(addCat(_:)))
        add.isEnabled = scene.activeCount < scene.roster.count
        menu.addItem(add)
        let remove = item(tr("Убрать котика", "Remove a cat"), #selector(removeCat(_:)))
        remove.isEnabled = scene.activeCount > 1
        menu.addItem(remove)

        let custom = scene.roster.filter { $0.breed.custom }
        func catList(_ cats: [Cat], _ action: Selector) -> [NSMenuItem] {
            return cats.map {
                let row = item($0.breed.displayName, action)
                row.representedObject = $0.breed.key
                return row
            }
        }
        let workshop = item(tr("Сделать из фото…", "Make from a photo…"), #selector(openCatWorkshop(_:)))
        workshop.isEnabled = scene.canAddCustomCat
        var ownItems = [workshop, NSMenuItem.separator()]
        let kitten = submenu(tr("Завести котёнка", "Adopt a kitten"), "kitten",
                             items: catList(scene.roster.filter { !$0.breed.kitten }, #selector(adoptKitten(_:))))
        kitten.isEnabled = scene.canAddCustomCat
        ownItems.append(kitten)
        if !custom.isEmpty {
            ownItems.append(submenu(tr("Изменить", "Edit"), "editCat", items: catList(custom, #selector(editCustomCat(_:)))))
            ownItems.append(submenu(tr("Удалить", "Delete"), "deleteCat", items: catList(custom, #selector(deleteCustomCat(_:)))))
        }
        menu.addItem(submenu(tr("Свои коты", "My cats"), "own", items: ownItems))
        let gif = item(CatRecorder.shared.isRecording ? tr("Записываю…", "Recording…") : tr("Записать GIF (5 секунд)", "Record a GIF (5 seconds)"),
                       #selector(recordGIF(_:)))
        gif.isEnabled = !CatRecorder.shared.isRecording && !scene.paused
        menu.addItem(gif)
        menu.addItem(NSMenuItem.separator())

        for cat in scene.roster {
            let breed = cat.breed
            let kind = breed.kitten ? tr("котёнок", "kitten") : (breed.custom ? tr("мой кот", "my cat") : breed.displayKind)
            let row = item("\(breed.displayName) — \(kind)", #selector(toggleCat(_:)), on: scene.isEnabled(breed.key))
            row.representedObject = breed.key
            menu.addItem(row)
        }
        menu.addItem(NSMenuItem.separator())

        for (mode, title) in [(0, tr("Ночь по часам", "Night by the clock")), (1, tr("Всегда ночь", "Always night")), (2, tr("Всегда день", "Always day"))] {
            let night = item(title, #selector(setCatsNight(_:)), on: scene.nightMode == mode)
            night.tag = mode
            menu.addItem(night)
        }
        let backgrounds: [NSMenuItem] = CatBackdrop.allCases.map {
            let row = item($0.title, #selector(setCatsBackground(_:)), on: CatBackdrop.current == $0)
            row.representedObject = $0.rawValue
            return row
        }
        menu.addItem(submenu(tr("Фон", "Background"), "background", items: backgrounds))
    }

    @objc func openAccessibilitySettings(_: Any?) {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as NSDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func addCat(_: Any?) {
        CatScene.shared.addCat()
    }

    @objc func removeCat(_: Any?) {
        CatScene.shared.removeCat()
    }

    @objc func toggleCat(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        CatScene.shared.setEnabled(id, item.state != .on)
    }

    @objc func deleteCustomCat(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        CatScene.shared.deleteCustomCat(id)
    }

    @objc func openCatWorkshop(_: Any?) {
        CatWorkshop.shared.show()
    }

    @objc func adoptKitten(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let parent = CatScene.shared.roster.first(where: { $0.breed.key == id }) else { return }
        CatScene.shared.addCustomCat(CustomCat.kitten(of: parent.breed))
    }

    @objc func editCustomCat(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let cat = CatScene.shared.roster.first(where: { $0.breed.key == id }) else { return }
        CatWorkshop.shared.show(record: CustomCatStore.load().first { $0.id == id } ?? CustomCat(breed: cat.breed, id: id))
    }

    @objc func recordGIF(_: Any?) {
        CatRecorder.shared.start()
    }

    @objc func setCatsBackground(_ item: NSMenuItem) {
        CatBackdrop.current = (item.representedObject as? String).flatMap(CatBackdrop.init(rawValue:)) ?? .black
    }

    @objc func setCatsNight(_ item: NSMenuItem) {
        CatScene.shared.nightMode = item.tag
    }
}
