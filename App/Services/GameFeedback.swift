import AVFoundation
import CoreHaptics
import QuartzCore
import UIKit

/// Event feedback. PCM and haptic patterns are prepared before the simulation starts;
/// no audio render callback reads game state or allocates memory.
@MainActor
final class GameFeedback {
    var soundEnabled = true {
        didSet {
            guard isActive, soundEnabled != oldValue else { return }
            if soundEnabled { startAudio() } else { stopAudio() }
        }
    }

    var hapticsEnabled = true {
        didSet {
            guard isActive, hapticsEnabled != oldValue else { return }
            if hapticsEnabled { startHaptics() } else { stopHaptics() }
        }
    }

    private let audioEngine = AVAudioEngine()
    private let impactNode = AVAudioPlayerNode()
    private let effectNode = AVAudioPlayerNode()
    private let clack: AVAudioPCMBuffer?
    private let fallTone: AVAudioPCMBuffer?
    private let winChord: AVAudioPCMBuffer?
    private let tapTone: AVAudioPCMBuffer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var hapticEngine: CHHapticEngine?
    private var impactPlayers: [any CHHapticPatternPlayer] = []
    private var fallPlayer: (any CHHapticPatternPlayer)?
    private var winPlayer: (any CHHapticPatternPlayer)?
    private var tapPlayer: (any CHHapticPatternPlayer)?
    private var impactFallback: UIImpactFeedbackGenerator?
    private var notificationFallback: UINotificationFeedbackGenerator?
    private var selectionFallback: UISelectionFeedbackGenerator?
    private var isActive = false
    private var hapticRunning = false
    private var audioPrepared = false
    private var audioSessionActive = false
    private var lastImpactTime = -Double.infinity
    private var lastTapTime = -Double.infinity

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        clack = Self.makeBuffer(format: format, duration: 0.052, kind: .clack)
        fallTone = Self.makeBuffer(format: format, duration: 0.34, kind: .fall)
        winChord = Self.makeBuffer(format: format, duration: 0.58, kind: .win)
        tapTone = Self.makeBuffer(format: format, duration: 0.025, kind: .tap)
        if let format {
            audioEngine.attach(impactNode)
            audioEngine.attach(effectNode)
            do {
                try audioEngine.connectNode(impactNode, to: audioEngine.mainMixerNode, format: format)
                try audioEngine.connectNode(effectNode, to: audioEngine.mainMixerNode, format: format)
                audioEngine.mainMixerNode.outputVolume = 0.65
                audioEngine.prepare()
                audioPrepared = true
            } catch {
                // A failed audio graph leaves haptic feedback available.
            }
        }
    }

    /// Call when entering active gameplay. This does not change the user's volume.
    func start() {
        isActive = true
        lastImpactTime = -Double.infinity
        lastTapTime = -Double.infinity
        if soundEnabled { startAudio() }
        if hapticsEnabled { startHaptics() }
    }

    /// Call on pause, backgrounding, and departure from the board.
    func stop() {
        isActive = false
        stopHaptics()
        stopAudio()
    }

    /// Normalized collision strength in 0...1. Contacts below the threshold are quiet.
    func impact(_ strength: Double) {
        guard isActive, strength.isFinite else { return }
        let amount = min(1, max(0, strength))
        let now = CACurrentMediaTime()
        guard amount >= 0.035, now - lastImpactTime >= 0.075 else { return }
        lastImpactTime = now
        play(clack, on: impactNode, volume: Float(0.22 + amount * 0.48))
        guard hapticsEnabled, supportsHaptics else { return }
        if !hapticRunning { startHaptics() }
        let index = amount < 0.25 ? 0 : (amount < 0.65 ? 1 : 2)
        if impactPlayers.indices.contains(index), playHaptic(impactPlayers[index]) { return }
        impactFallback?.impactOccurred(intensity: CGFloat(0.15 + amount * 0.55))
    }

    func fall() {
        guard isActive else { return }
        play(fallTone, on: effectNode, volume: 0.68)
        guard hapticsEnabled, supportsHaptics else { return }
        if !hapticRunning { startHaptics() }
        if !playHaptic(fallPlayer) { notificationFallback?.notificationOccurred(.warning) }
    }

    func win() {
        guard isActive else { return }
        play(winChord, on: effectNode, volume: 0.58)
        guard hapticsEnabled, supportsHaptics else { return }
        if !hapticRunning { startHaptics() }
        if !playHaptic(winPlayer) { notificationFallback?.notificationOccurred(.success) }
    }

    func tap() {
        guard isActive else { return }
        let now = CACurrentMediaTime()
        guard now - lastTapTime >= 0.09 else { return }
        lastTapTime = now
        play(tapTone, on: impactNode, volume: 0.28)
        guard hapticsEnabled, supportsHaptics else { return }
        if !hapticRunning { startHaptics() }
        if !playHaptic(tapPlayer) { selectionFallback?.selectionChanged() }
    }

    private func startAudio() {
        guard isActive, soundEnabled, audioPrepared, !audioEngine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Ambient respects the silent switch and allows the player's music to continue.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            audioSessionActive = true
            try audioEngine.start()
        } catch {
            stopAudio()
        }
    }

    private func stopAudio() {
        impactNode.stop()
        effectNode.stop()
        audioEngine.stop()
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            audioSessionActive = false
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer?, on node: AVAudioPlayerNode, volume: Float) {
        guard isActive, soundEnabled, audioEngine.isRunning, let buffer else { return }
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !node.isPlaying {
            do { try node.playAudio() } catch { node.stop() }
        }
    }

    private func startHaptics() {
        guard isActive, hapticsEnabled, supportsHaptics, !hapticRunning else { return }
        if impactFallback == nil {
            impactFallback = UIImpactFeedbackGenerator(style: .soft)
            notificationFallback = UINotificationFeedbackGenerator()
            selectionFallback = UISelectionFeedbackGenerator()
        }
        impactFallback?.prepare()
        notificationFallback?.prepare()
        selectionFallback?.prepare()
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            if hapticEngine == nil {
                let engine = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
                engine.playsHapticsOnly = true
                engine.isMutedForAudio = true
                engine.isAutoShutdownEnabled = false
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in self?.hapticRunning = false }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.impactPlayers.removeAll()
                        self.fallPlayer = nil
                        self.winPlayer = nil
                        self.tapPlayer = nil
                        self.hapticRunning = false
                        self.startHaptics()
                    }
                }
                hapticEngine = engine
            }
            guard let engine = hapticEngine else { return }
            try engine.start()
            if impactPlayers.isEmpty {
                impactPlayers = try [0.16, 0.32, 0.52].map {
                    try Self.makeHapticPlayer(engine: engine, pulses: [(0, Float($0), 0.35)])
                }
                fallPlayer = try Self.makeHapticPlayer(engine: engine, pulses: [(0, 0.36, 0.25), (0.08, 0.18, 0.15)])
                winPlayer = try Self.makeHapticPlayer(engine: engine, pulses: [(0, 0.22, 0.3), (0.09, 0.34, 0.4), (0.2, 0.48, 0.5)])
                tapPlayer = try Self.makeHapticPlayer(engine: engine, pulses: [(0, 0.14, 0.3)])
            }
            hapticRunning = true
        } catch {
            hapticRunning = false
        }
    }

    private func stopHaptics() {
        hapticEngine?.stop(completionHandler: nil)
        hapticRunning = false
    }

    private func playHaptic(_ player: (any CHHapticPatternPlayer)?) -> Bool {
        guard hapticRunning, let player else { return false }
        do {
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            hapticRunning = false
            return false
        }
    }

    private static func makeHapticPlayer(
        engine: CHHapticEngine,
        pulses: [(time: TimeInterval, intensity: Float, sharpness: Float)]
    ) throws -> any CHHapticPatternPlayer {
        let events = pulses.map { pulse in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness)
            ], relativeTime: pulse.time)
        }
        return try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
    }

    private enum SoundKind { case clack, fall, win, tap }

    private static func makeBuffer(format: AVAudioFormat?, duration: Double, kind: SoundKind) -> AVAudioPCMBuffer? {
        guard let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * format.sampleRate)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        var noise: UInt64 = 0x4C49_4C54
        let twoPi = 2 * Double.pi
        for frame in 0..<Int(buffer.frameLength) {
            let time = Double(frame) / format.sampleRate
            let attack = min(1, time / 0.0015)
            let tail = min(1, (duration - time) / 0.008)
            let sample: Double
            switch kind {
            case .clack:
                noise = noise &* 6_364_136_223_846_793_005 &+ 1
                let grain = Double((noise >> 40) & 0xFFFF) / 32_767.5 - 1
                sample = (0.09 * sin(twoPi * 820 * time) + 0.045 * sin(twoPi * 2_310 * time) + 0.025 * grain) * exp(-time * 90)
            case .fall:
                let phase = twoPi * (510 * time - 380 * time * time)
                sample = 0.12 * sin(phase) * exp(-time * 9)
            case .win:
                sample = (sin(twoPi * 523.25 * time) + 0.8 * sin(twoPi * 659.25 * time) + 0.65 * sin(twoPi * 783.99 * time)) * 0.043 * exp(-time * 5)
            case .tap:
                sample = 0.08 * sin(twoPi * 1_100 * time) * exp(-time * 140)
            }
            samples[frame] = Float(sample * attack * tail)
        }
        return buffer
    }
}
