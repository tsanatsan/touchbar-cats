//
//  CatSounds.swift
//  MTMR
//
//  Quiet synthesized cat sounds: purring while petted, "mrrp" for a caught letter, "meow" as an answer.
//  Off by default. The audio engine runs only while something sounds and stops after a few quiet seconds.
//

import AVFoundation

final class CatSounds {
    static let shared = CatSounds()

    enum Kind { case mrrp, meow }

    private struct Voice {
        var kind: Kind
        var time: Double
        var pan: Float
    }

    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var voices: [Voice] = []
    private var purrTarget: Float = 0
    private var purrLevel: Float = 0
    private var purrPan: Float = 0
    private var purrTime: Double = 0
    private var noise: Float = 0
    private var lastSound = CACurrentMediaTime()

    private var enabled: Bool { return AppSettings.catSounds }

    func play(_ kind: Kind, pan: CGFloat) {
        guard enabled else { return }
        start()
        lock.lock()
        if voices.count < 6 { voices.append(Voice(kind: kind, time: 0, pan: Float(pan))) }
        lock.unlock()
        lastSound = CACurrentMediaTime()
    }

    func setPurr(_ on: Bool, pan: CGFloat) {
        let target: Float = on && enabled ? 1 : 0
        if target > 0 {
            start()
            lastSound = CACurrentMediaTime()
        }
        lock.lock()
        purrTarget = target
        purrPan = Float(pan)
        lock.unlock()
    }

    /// Called every frame: stops the engine after a quiet moment to save power
    func tick() {
        guard let engine = engine else { return }
        lock.lock()
        let quiet = voices.isEmpty && purrLevel < 0.001 && purrTarget == 0
        lock.unlock()
        if !enabled || (quiet && CACurrentMediaTime() - lastSound > 3) {
            engine.stop()
            self.engine = nil
        }
    }

    private func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate > 0 ? engine.outputNode.outputFormat(forBus: 0).sampleRate : 44100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let dt = 1 / rate
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self = self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.lock.lock()
            for i in 0 ..< Int(frameCount) {
                var l: Float = 0, r: Float = 0
                // purr: low rumbling noise pulsing ~26 times a second
                self.purrLevel += (self.purrTarget - self.purrLevel) * 0.0004
                if self.purrLevel > 0.0005 {
                    self.purrTime += dt
                    self.noise += (Float.random(in: -1 ... 1) - self.noise) * 0.02
                    let pulse = Float(0.5 + 0.5 * sin(2 * .pi * 26 * self.purrTime))
                    let s = self.noise * pulse * pulse * self.purrLevel * 1.4
                    l += s * Float(cos(Double(self.purrPan + 1) * .pi / 4))
                    r += s * Float(sin(Double(self.purrPan + 1) * .pi / 4))
                }
                for v in self.voices.indices {
                    let s = CatSounds.sample(self.voices[v].kind, at: self.voices[v].time)
                    let p = Double(self.voices[v].pan + 1) * .pi / 4
                    l += s * Float(cos(p))
                    r += s * Float(sin(p))
                    self.voices[v].time += dt
                }
                left[i] = l
                right[i] = r
            }
            self.voices.removeAll { $0.time > ($0.kind == .mrrp ? 0.25 : 0.6) }
            self.lock.unlock()
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.35
        do {
            try engine.start()
            self.engine = engine
        } catch {
            NSLog("TouchBar Cats: sound engine failed: \(error)")
        }
    }

    /// A tiny voice: a pitch sweep with a soft envelope and a little vibrato
    private static func sample(_ kind: Kind, at t: Double) -> Float {
        let (duration, f0, f1, f2): (Double, Double, Double, Double) = kind == .mrrp ? (0.22, 520, 880, 760) : (0.55, 650, 1050, 600)
        guard t < duration else { return 0 }
        let k = t / duration
        let freq = k < 0.4 ? f0 + (f1 - f0) * (k / 0.4) : f1 + (f2 - f1) * ((k - 0.4) / 0.6)
        let vibrato = 1 + 0.015 * sin(2 * .pi * 7 * t)
        let phase = 2 * .pi * freq * vibrato * t
        let envelope = min(1, t / 0.02) * min(1, (duration - t) / 0.08)
        let tone = sin(phase) + 0.35 * sin(2 * phase) + 0.12 * sin(3 * phase)
        return Float(tone * envelope * (kind == .mrrp ? 0.16 : 0.14))
    }
}
