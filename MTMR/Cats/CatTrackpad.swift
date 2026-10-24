//
//  CatTrackpad.swift
//  MTMR
//
//  Where the finger is on the built-in trackpad, for the laser pointer. Read through the private
//  MultitouchSupport framework (the same one gesture tools use), loaded at runtime. The callback fires
//  only while a finger touches the trackpad, so it costs nothing the rest of the time.
//

import Foundation
import QuartzCore

final class CatTrackpad {
    static let shared = CatTrackpad()

    struct Finger {
        var x: CGFloat // 0 left ... 1 right
        var y: CGFloat // 0 near edge ... 1 far edge
        var count: Int // fingers on the trackpad
        var time: CFTimeInterval
    }

    /// Trackpad size in millimeters (0 until known)
    private(set) var widthMM: CGFloat = 0

    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer?, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer?) -> Bool
    private typealias Dimensions = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    private let lock = NSLock()
    private var latest: Finger?
    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFMutableArray?
    private var running = false
    private var tried = false // no built-in trackpad: don't look for it again every frame

    private lazy var framework: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)

    private func symbol<T>(_ name: String, _: T.Type) -> T? {
        guard let lib = framework, let sym = dlsym(lib, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// The last finger seen on the trackpad
    var finger: Finger? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func start() {
        guard !running, !tried else { return }
        tried = true
        guard let createList = symbol("MTDeviceCreateList", CreateList.self),
              let register = symbol("MTRegisterContactFrameCallback", Register.self),
              let startDevice = symbol("MTDeviceStart", Start.self),
              let list = createList()?.takeRetainedValue() else { return }
        let isBuiltIn = symbol("MTDeviceIsBuiltIn", IsBuiltIn.self)
        let dimensions = symbol("MTDeviceGetSensorSurfaceDimensions", Dimensions.self)
        deviceList = list
        devices = []
        for i in 0 ..< CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            if let builtIn = isBuiltIn, !builtIn(device) { continue } // the laser maps the trackpad under the Touch Bar
            // the Touch Bar is a multitouch device too: a strip under a centimeter deep, the trackpad is several
            guard let dimensions = dimensions else { continue }
            var w: Int32 = 0, h: Int32 = 0
            guard dimensions(device, &w, &h) == 0, w > 0, h > 3000 else { continue }
            widthMM = CGFloat(w) / 100
            register(device, CatTrackpad.contacts)
            startDevice(device, 0)
            devices.append(device)
        }
        running = !devices.isEmpty
    }

    func stop() {
        tried = false
        guard running else { return }
        if let stopDevice = symbol("MTDeviceStop", Stop.self) {
            devices.forEach { stopDevice($0) }
        }
        devices = []
        deviceList = nil
        running = false
        lock.lock()
        latest = nil
        lock.unlock()
    }

    /// After sleep the trackpad comes back as a new device
    func restart() {
        guard running else { return }
        stop()
        start()
    }

    // MTTouch is 96 bytes: state at 20, normalized position (x, y) at 32 and 36
    private static let contacts: Callback = { _, touches, count, _, _ in
        let pad = CatTrackpad.shared
        var finger: Finger?
        if let touches = touches, count > 0 {
            var down = 0
            var x: Float = 0, y: Float = 0
            for i in 0 ..< Int(count) {
                let touch = touches + i * 96
                let state = touch.load(fromByteOffset: 20, as: Int32.self)
                guard state == 4 || state == 5 else { continue } // touching, not hovering or lifting
                down += 1
                x += touch.load(fromByteOffset: 32, as: Float.self)
                y += touch.load(fromByteOffset: 36, as: Float.self)
            }
            if down > 0 {
                finger = Finger(x: CGFloat(x) / CGFloat(down), y: CGFloat(y) / CGFloat(down), count: down, time: CACurrentMediaTime())
            }
        }
        pad.lock.lock()
        pad.latest = finger
        pad.lock.unlock()
        return 0
    }
}
