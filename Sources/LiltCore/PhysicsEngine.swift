import Foundation

/// A deterministic, fixed-step rolling-ball simulation. SwiftUI and display refresh rates
/// never own the integration clock; the same input at 60 Hz or 120 Hz yields the same state.
public struct PhysicsEngine: Sendable {
    public let level: MazeLevel
    public var position: Vec2
    public var velocity: Vec2
    public private(set) var status: PhysicsStatus = .ready
    public private(set) var elapsed: Double = 0
    public private(set) var fallProgress: Double = 0

    public static let fixedTimeStep = 1.0 / 240.0
    /// A solid sphere's 5/7 rolling factor, expressed through the game's board-space gain.
    public static let rollingGravity = 9.81 * (5.0 / 7.0) * 0.70
    /// Light speed-dependent drag, in inverse seconds.
    public static let viscousDrag = 0.50
    /// Constant rolling resistance, in board widths per second squared. Unlike viscous
    /// drag alone, it dissipates the last of the marble's momentum in finite time.
    public static let rollingFriction = 0.008
    /// A resting marble only breaks away when downhill acceleration overcomes resistance.
    public static let breakawayAcceleration = rollingFriction
    /// Extra dissipation while the player tilts against the marble's travel. It acts
    /// only along that opposing input, leaving launch response and sideways momentum intact.
    private static let reverseTiltDrag = 3.0
    /// Smooth input activation in board-space tilt units, rather than a braking threshold.
    private static let brakingTiltScale = 0.06
    private var accumulator: Double = 0
    private var fallTarget: Vec2 = .zero

    public init(level: MazeLevel) {
        self.level = level
        self.position = level.start
        self.velocity = .zero
    }

    public mutating func reset() {
        position = level.start; velocity = .zero; status = .ready
        elapsed = 0; fallProgress = 0; accumulator = 0; fallTarget = .zero
    }

    public mutating func start() {
        guard status == .ready else { return }
        status = .playing
    }

    /// Tilt is a board-space gravity component: positive x rolls right, positive y down.
    /// No automatic travel, goal steering, or force along the solution route is applied.
    public mutating func step(dt: Double, tilt: Vec2) -> [PhysicsEvent] {
        guard dt.isFinite, dt > 0, status != .ready, status != .won else { return [] }
        // A suspended scene must pause its own clock. Bounded catch-up avoids a multi-second
        // simulation burst on a display callback after the application returns to foreground.
        accumulator += min(dt, 0.25)
        var events: [PhysicsEvent] = []
        let safeTilt = Vec2(tilt.x.isFinite ? tilt.x : 0, tilt.y.isFinite ? tilt.y : 0)
        let boundedTilt = safeTilt.length > 1 ? safeTilt.normalized : safeTilt
        while accumulator + 1e-12 >= Self.fixedTimeStep {
            accumulator -= Self.fixedTimeStep
            if accumulator < 0 { accumulator = 0 }
            let h = Self.fixedTimeStep
            if status == .falling {
                fallProgress = min(1, fallProgress + h / 0.48)
                position += (fallTarget - position) * min(1, h * 14)
                velocity *= exp(-h * 10)
                continue
            }
            if status != .playing { accumulator = 0; break }
            elapsed += h
            simulate(h: h, tilt: boundedTilt, events: &events)
        }
        return events
    }

    private mutating func simulate(h: Double, tilt: Vec2, events: inout [PhysicsEvent]) {
        // Adaptive inner substeps keep contacts well-conditioned at exceptional velocities;
        // swept capsule intersections below provide the actual anti-tunnelling guarantee.
        let travel = velocity.length * h + Self.rollingGravity * h * h
        let count = min(128, max(1, Int(ceil(travel / max(0.003, level.ballRadius * 0.45)))))
        let substep = h / Double(count)
        for _ in 0..<count {
            guard status == .playing else { break }
            dampOpposingMomentum(tilt: tilt, duration: substep)
            var acceleration = tilt * Self.rollingGravity
            for feature in level.features {
                let delta = feature.center - position
                // Reach into adjacent corridors so a protected route can still teach the
                // player to counter a field without putting a solid object across it.
                let range = max(0.24, feature.radius * 6.5)
                let distance = delta.length
                guard distance < range else { continue }
                let envelope = (1 - distance / range) * (1 - distance / range)
                switch feature.kind {
                case .magnet:
                    // A softened field, without the singularity of an inverse-square force.
                    acceleration += delta.normalized * (1.7 * envelope)
                case .fan:
                    acceleration += feature.direction.normalized * (1.45 * envelope)
                case .bumper: break
                }
            }
            let decay = exp(-Self.viscousDrag * substep)
            let response = (1 - decay) / Self.viscousDrag
            if velocity.lengthSquared < 1e-20, acceleration.length <= Self.breakawayAcceleration {
                velocity = .zero
            } else {
                // Integrate gravity/drag, then remove the speed consumed by rolling
                // resistance. Clamping at zero prevents friction from reversing the
                // marble or generating chatter at rest. In one-dimensional neutral
                // coasting this is the exact Coulomb-plus-viscous velocity solution.
                let unconstrained = velocity * decay + acceleration * response
                let speed = unconstrained.length
                let remainingSpeed = max(0, speed - Self.rollingFriction * response)
                velocity = speed > 0 && remainingSpeed > 0 ? unconstrained * (remainingSpeed / speed) : .zero
            }
            resolvePenetration()
            moveSwept(duration: substep, events: &events)
        }
    }

    private mutating func dampOpposingMomentum(tilt: Vec2, duration: Double) {
        let magnitude = tilt.length
        guard magnitude > 0 else { return }
        let direction = tilt / magnitude
        let alongTilt = velocity.dot(direction)
        guard alongTilt < 0 else { return }
        let activation = magnitude / (magnitude + Self.brakingTiltScale)
        let dissipatedFraction = -expm1(-Self.reverseTiltDrag * activation * duration)
        // Exponential damping removes only opposing momentum and cannot reverse it.
        // Its force fades continuously as speed reaches zero. Gravity then supplies
        // normal acceleration, so holding the reverse tilt still rolls the other way.
        velocity += direction * (-alongTilt * dissipatedFraction)
    }

    private mutating func resolvePenetration() {
        let radius = level.ballRadius
        for _ in 0..<4 {
            var corrected = false
            for wall in level.walls {
                let closest = Geometry.closestPoint(on: wall.a, wall.b, to: position)
                let offset = position - closest
                let contactRadius = radius + wall.thickness * 0.5
                if offset.length < contactRadius - 1e-9 {
                    let normal: Vec2
                    if offset.length > 1e-10 {
                        normal = offset.normalized
                    } else {
                        let along = (wall.b - wall.a).normalized
                        var candidate = Vec2(-along.y, along.x)
                        if velocity.dot(candidate) > 0 { candidate = -candidate }
                        normal = candidate.length > 0 ? candidate : Vec2(1, 0)
                    }
                    position = closest + normal * (contactRadius + 1e-7)
                    let inward = velocity.dot(normal)
                    if inward < 0 { velocity -= normal * inward }
                    corrected = true
                }
            }
            for bumper in level.features where bumper.kind == .bumper {
                let offset = position - bumper.center
                let contactRadius = radius + bumper.radius
                if offset.length < contactRadius - 1e-9 {
                    let normal = offset.length > 1e-10 ? offset.normalized : Vec2(1, 0)
                    position = bumper.center + normal * (contactRadius + 1e-7)
                    let inward = velocity.dot(normal)
                    if inward < 0 { velocity -= normal * inward }
                    corrected = true
                }
            }
            position.x = min(level.width - radius, max(radius, position.x))
            position.y = min(level.height - radius, max(radius, position.y))
            if !corrected { break }
        }
    }

    private mutating func moveSwept(duration: Double, events: inout [PhysicsEvent]) {
        var remaining = duration
        for _ in 0..<8 {
            guard remaining > 1e-10, status == .playing else { break }
            let movement = velocity * remaining
            var collision: SweepHit?
            for wall in level.walls {
                let hit = Geometry.sweepCircle(position: position, movement: movement,
                                               a: wall.a, b: wall.b,
                                               radius: level.ballRadius + wall.thickness * 0.5)
                if let hit, collision == nil || hit.time < collision!.time { collision = hit }
            }
            let boundaries = [
                (Vec2(0, 0), Vec2(level.width, 0)),
                (Vec2(level.width, 0), Vec2(level.width, level.height)),
                (Vec2(level.width, level.height), Vec2(0, level.height)),
                (Vec2(0, level.height), Vec2(0, 0))
            ]
            for (a, b) in boundaries {
                let hit = Geometry.sweepCircle(position: position, movement: movement,
                                               a: a, b: b, radius: level.ballRadius)
                if let hit, collision == nil || hit.time < collision!.time { collision = hit }
            }
            for feature in level.features where feature.kind == .bumper {
                if var hit = Geometry.sweepCircle(position: position, movement: movement,
                                                  a: feature.center, b: feature.center,
                                                  radius: level.ballRadius + feature.radius) {
                    hit.restitution = 0.88
                    hit.bumper = true
                    if collision == nil || hit.time < collision!.time { collision = hit }
                }
            }
            let contactTime = collision?.time ?? 1
            if let capture = firstCapture(movement: movement, before: contactTime) {
                position += movement * capture.time
                if capture.isGoal {
                    position = level.goal; velocity = .zero; status = .won
                    events.append(.won)
                } else {
                    fallTarget = capture.center; status = .falling; fallProgress = 0
                    events.append(.fell)
                }
                return
            }
            guard let hit = collision else { position += movement; return }
            position += movement * hit.time + hit.normal * 1e-7
            let inward = velocity.dot(hit.normal)
            if inward < 0 {
                let strength = -inward
                velocity -= hit.normal * ((1 + hit.restitution) * inward)
                if hit.bumper { velocity += hit.normal * 0.12 }
                if strength > 0.065 { events.append(.impact(min(1, strength / 1.3))) }
            }
            remaining *= max(0, 1 - hit.time)
        }
    }

    private func firstCapture(movement: Vec2, before: Double) -> Capture? {
        var result: Capture?
        for hole in level.holes where hole.radius > level.ballRadius * 0.9 {
            let captureRadius = max(hole.radius * 0.55, hole.radius - level.ballRadius * 0.35)
            if let time = Geometry.circleEntry(position: position, movement: movement,
                                                center: hole.center, radius: captureRadius), time <= before {
                if result == nil || time < result!.time {
                    result = Capture(time: time, center: hole.center, isGoal: false)
                }
            }
        }
        if let time = Geometry.circleEntry(position: position, movement: movement,
                                           center: level.goal, radius: level.ballRadius * 1.2),
           time <= before, result == nil || time < result!.time {
            result = Capture(time: time, center: level.goal, isGoal: true)
        }
        return result
    }
}

private struct Capture { var time: Double; var center: Vec2; var isGoal: Bool }
struct SweepHit { var time: Double; var normal: Vec2; var restitution: Double = 0.14; var bumper = false }

enum Geometry {
    static func closestPoint(on a: Vec2, _ b: Vec2, to point: Vec2) -> Vec2 {
        let along = b - a
        guard along.lengthSquared > 1e-16 else { return a }
        let t = min(1, max(0, (point - a).dot(along) / along.lengthSquared))
        return a + along * t
    }

    static func pointSegmentDistance(_ point: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        point.distance(to: closestPoint(on: a, b, to: point))
    }

    static func circleEntry(position: Vec2, movement: Vec2, center: Vec2, radius: Double) -> Double? {
        let offset = position - center
        let c = offset.lengthSquared - radius * radius
        if c <= 0 { return 0 }
        let a = movement.lengthSquared
        guard a > 1e-18 else { return nil }
        let b = 2 * offset.dot(movement)
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let t = (-b - sqrt(discriminant)) / (2 * a)
        return t >= -1e-10 && t <= 1 + 1e-10 ? min(1, max(0, t)) : nil
    }

    /// Earliest intersection with a capsule: finite strip plus both circular end caps.
    static func sweepCircle(position: Vec2, movement: Vec2, a: Vec2, b: Vec2, radius: Double) -> SweepHit? {
        guard movement.lengthSquared > 1e-18 else { return nil }
        let along = b - a
        let length = along.length
        var earliest: SweepHit?
        for end in [a, b] {
            if let t = circleEntry(position: position, movement: movement, center: end, radius: radius) {
                let offset = position + movement * t - end
                let normal = offset.length > 1e-12 ? offset.normalized : -movement.normalized
                if movement.dot(normal) < -1e-12 {
                    let hit = SweepHit(time: t, normal: normal)
                    if earliest == nil || t < earliest!.time { earliest = hit }
                }
            }
        }
        if length > 1e-12 {
            let tangent = along / length
            let perpendicular = Vec2(-tangent.y, tangent.x)
            let signedDistance = (position - a).dot(perpendicular)
            let speed = movement.dot(perpendicular)
            if abs(speed) > 1e-14 {
                for side in [-1.0, 1.0] {
                    let t = (side * radius - signedDistance) / speed
                    guard t >= -1e-10, t <= 1 + 1e-10 else { continue }
                    let normal = perpendicular * side
                    guard movement.dot(normal) < -1e-12 else { continue }
                    let point = position + movement * max(0, t)
                    let projection = (point - a).dot(tangent)
                    if projection >= -1e-10, projection <= length + 1e-10 {
                        let hit = SweepHit(time: min(1, max(0, t)), normal: normal)
                        if earliest == nil || hit.time < earliest!.time { earliest = hit }
                    }
                }
            }
        }
        return earliest
    }
}
