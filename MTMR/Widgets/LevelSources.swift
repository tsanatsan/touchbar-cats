//
//  LevelSources.swift
//  MTMR
//
//  System values (volume, display brightness) in 0...1 for ControlStripSliderItem.
//

import AppKit
import AudioToolbox
import CoreAudio

protocol LevelSource: AnyObject {
    var level: Float { get set }
    /// Called on the main queue when the value was changed outside of MTMR (keyboard, Control Center)
    var onExternalChange: (() -> Void)? { get set }
    var minImage: NSImage? { get }
    var maxImage: NSImage? { get }
    func image(for level: Float) -> NSImage?
}

func controlStripSymbol(_ name: String) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

// MARK: - Volume

final class VolumeLevel: LevelSource {
    var onExternalChange: (() -> Void)?
    private var deviceID = AudioObjectID(0)
    private var deviceListener: AudioObjectPropertyListenerBlock!
    private var routeListener: AudioObjectPropertyListenerBlock!

    let minImage = controlStripSymbol("speaker.fill")
    let maxImage = controlStripSymbol("speaker.wave.3.fill")

    init() {
        deviceListener = { [weak self] _, _ in self?.onExternalChange?() }
        routeListener = { [weak self] _, _ in
            guard let self = self else { return }
            self.observeDevice(false)
            self.deviceID = VolumeLevel.defaultOutputDevice()
            self.observeDevice(true)
            self.onExternalChange?()
        }
        deviceID = VolumeLevel.defaultOutputDevice()
        var route = VolumeLevel.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &route, .main, routeListener)
        observeDevice(true)
    }

    deinit {
        observeDevice(false)
        var route = VolumeLevel.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &route, .main, routeListener)
    }

    var level: Float {
        get {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = VolumeLevel.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
            return volume
        }
        set {
            var volume = Float32(min(max(newValue, 0), 1))
            var address = VolumeLevel.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
            isMuted = volume == 0
        }
    }

    var isMuted: Bool {
        get {
            var mute: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = VolumeLevel.address(kAudioDevicePropertyMute)
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
            return mute != 0
        }
        set {
            var mute: UInt32 = newValue ? 1 : 0
            var address = VolumeLevel.address(kAudioDevicePropertyMute)
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        }
    }

    func image(for level: Float) -> NSImage? {
        switch level {
        case _ where isMuted || level == 0: return controlStripSymbol("speaker.slash.fill")
        case ..<0.34: return controlStripSymbol("speaker.wave.1.fill")
        case ..<0.67: return controlStripSymbol("speaker.wave.2.fill")
        default: return controlStripSymbol("speaker.wave.3.fill")
        }
    }

    private func observeDevice(_ observe: Bool) {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = VolumeLevel.address(selector)
            if observe {
                AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, deviceListener)
            } else {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, deviceListener)
            }
        }
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMaster)
    }
}

// MARK: - Display brightness

final class BrightnessLevel: LevelSource {
    var onExternalChange: (() -> Void)?
    private var timer: Timer?
    private var lastKnown: Float = -1

    let minImage = controlStripSymbol("sun.min.fill")
    let maxImage = controlStripSymbol("sun.max.fill")

    init(refreshInterval: Double) {
        // DisplayServices has no public change notification, so poll (cheap call)
        let timer = Timer(timeInterval: max(refreshInterval, 0.25), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = self.level
            if abs(current - self.lastKnown) > 0.004 {
                self.lastKnown = current
                self.onExternalChange?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    var level: Float {
        get {
            var level: Float = 0.5
            DisplayServicesGetBrightness(CGMainDisplayID(), &level)
            return level
        }
        set {
            lastKnown = min(max(newValue, 0), 1)
            DisplayServicesSetBrightness(CGMainDisplayID(), lastKnown)
        }
    }

    func image(for _: Float) -> NSImage? {
        return maxImage
    }
}
