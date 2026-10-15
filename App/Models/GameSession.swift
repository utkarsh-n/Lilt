import Foundation
import Observation
import LiltCore

@MainActor
@Observable
final class GameSession: BoardSceneSource {
    let level: MazeLevel
    private(set) var status: PhysicsStatus = .ready
    private(set) var displayedTime = 0.0
    private(set) var attempts = 1
    private(set) var isPaused = false
    private(set) var hasStarted = false
    var touchControl = false
    var sensitivity = 1.3
    var showRoute = false { didSet { if showRoute { usedHint = true } } }
    private(set) var usedHint = false
    var showGhost = true
    var onWin: ((Double, [ReplayPoint]) -> Void)?
    @ObservationIgnored private var engine: PhysicsEngine
    @ObservationIgnored private let motion = MotionInput()
    @ObservationIgnored let feedback = GameFeedback()
    @ObservationIgnored private var lastTimestamp: Double?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var lastDisplayUpdate = 0.0
    @ObservationIgnored private var touchTilt = Vec2.zero
    @ObservationIgnored private var nudgeUntil = 0.0
    @ObservationIgnored private var nudgeTilt = Vec2.zero
    @ObservationIgnored private var sampledTilt = Vec2.zero
    @ObservationIgnored private var replay: [ReplayPoint] = []
    @ObservationIgnored private var previousReplay: [ReplayPoint] = []
    @ObservationIgnored private var ghostIndex = 0
    @ObservationIgnored private var lastReplayTime = -1.0

    init(level: MazeLevel, previousReplay: [ReplayPoint] = []) {
        self.level = level
        self.previousReplay = previousReplay
        engine = PhysicsEngine(level: level)
        touchControl = !motion.isAvailable
    }

    var motionAvailable: Bool { motion.isAvailable }
    var isRunning: Bool { hasStarted && !isPaused && status != .won }

    func prepareControls() {
        if !touchControl { motion.start() }
    }

    func start() {
        let firstStart = !hasStarted
        if status == .ready { engine.start() }
        hasStarted = true
        isPaused = false
        status = engine.status
        lastTimestamp = nil
        accumulator = 0
        if !touchControl {
            motion.start()
            if firstStart { motion.calibrate() }
        }
        feedback.start()
    }

    func pause() {
        isPaused = true
        lastTimestamp = nil
        accumulator = 0
        touchTilt = .zero
        sampledTilt = .zero
        nudgeUntil = 0
        motion.stop()
        feedback.stop()
    }

    func resume() {
        guard hasStarted, status != .won else { return }
        start()
    }

    func restart() {
        engine.reset()
        displayedTime = 0
        attempts += hasStarted ? 1 : 0
        status = .ready
        replay.removeAll(keepingCapacity: true)
        lastReplayTime = -1
        ghostIndex = 0
        usedHint = showRoute
        touchTilt = .zero
        nudgeUntil = 0
        start()
        feedback.tap()
    }

    func calibrate() { motion.calibrate(); feedback.tap() }
    func setTouchTilt(_ value: Vec2) { touchTilt = value }

    func installBestReplay(_ points: [ReplayPoint]) {
        previousReplay = points
        ghostIndex = 0
    }

    func nudge(_ value: Vec2) {
        guard isRunning else { return }
        nudgeTilt = value * 0.35
        nudgeUntil = ProcessInfo.processInfo.systemUptime + 0.18
        feedback.tap()
    }

    func advanceFrame(timestamp: Double) {
        guard isRunning else { lastTimestamp = nil; return }
        guard let last = lastTimestamp else { lastTimestamp = timestamp; return }
        let dt = min(max(timestamp - last, 0), 0.08)
        lastTimestamp = timestamp
        sampledTilt = touchControl ? touchTilt : motion.sample(sensitivity: sensitivity)
        if ProcessInfo.processInfo.systemUptime < nudgeUntil { sampledTilt += nudgeTilt }
        accumulator += dt
        let fixedStep = 1.0 / 240.0
        while accumulator >= fixedStep {
            let events = engine.step(dt: fixedStep, tilt: sampledTilt)
            accumulator -= fixedStep
            for event in events {
                switch event {
                case .impact(let strength): feedback.impact(strength)
                case .fell: feedback.fall()
                case .won:
                    status = .won
                    displayedTime = engine.elapsed
                    replay.append(ReplayPoint(time: engine.elapsed, position: engine.position))
                    motion.stop()
                    feedback.win()
                    onWin?(engine.elapsed, replay)
                }
            }
            if engine.status == .won { accumulator = 0; break }
            if engine.status == .falling && engine.fallProgress >= 1 {
                engine.reset()
                engine.start()
                attempts += 1
                replay.removeAll(keepingCapacity: true)
                lastReplayTime = -1
                ghostIndex = 0
                usedHint = showRoute
                touchTilt = .zero
                accumulator = 0
                break
            }
            if engine.status == .playing && engine.elapsed - lastReplayTime >= 1 / 30.0 {
                // Bound persistent ghost data to ten minutes at 30 samples per second.
                if replay.count < 18_000 { replay.append(ReplayPoint(time: engine.elapsed, position: engine.position)) }
                lastReplayTime = engine.elapsed
            }
        }
        if status != engine.status { status = engine.status }
        if timestamp - lastDisplayUpdate >= 0.1 {
            displayedTime = engine.elapsed
            lastDisplayUpdate = timestamp
        }
    }

    func renderSnapshot() -> BoardRenderSnapshot {
        var ghost: Vec2?
        if showGhost, previousReplay.count > 1, hasStarted {
            while ghostIndex + 1 < previousReplay.count && previousReplay[ghostIndex + 1].time < engine.elapsed { ghostIndex += 1 }
            if ghostIndex + 1 < previousReplay.count {
                let a = previousReplay[ghostIndex], b = previousReplay[ghostIndex + 1]
                let t = min(1, max(0, (engine.elapsed - a.time) / max(0.001, b.time - a.time)))
                ghost = a.position + (b.position - a.position) * t
            }
        }
        return BoardRenderSnapshot(level: level, ballPosition: engine.position, ballRadius: level.ballRadius,
            tilt: sampledTilt, fallProgress: engine.fallProgress, ghostPosition: ghost,
            solutionVisible: showRoute, elapsed: engine.elapsed)
    }
}
