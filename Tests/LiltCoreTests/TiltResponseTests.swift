import Foundation
import Testing
@testable import LiltCore

@Test func smallPhysicalTiltsStartMovingOnTheFirstPhysicsStep() {
    for degrees in [0.25, 0.5, 1.0, 3.0] {
        for sign in [-1.0, 1.0] {
            for alongX in [true, false] {
                let component = sign * sin(degrees * Double.pi / 180)
                let raw = alongX ? Vec2(component, 0) : Vec2(0, component)
                let input = TiltResponse.apply(raw, sensitivity: 1.3)
                var engine = TiltResponseFixture.engine()
                let initial = engine.position
                _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: input)
                let speed = alongX ? engine.velocity.x : engine.velocity.y
                let displacement = alongX ? engine.position.x - initial.x : engine.position.y - initial.y
                #expect(speed * sign > 0, "\(degrees)° must accelerate on the first 240 Hz step")
                #expect(displacement * sign > 0)
                #expect(engine.status == .playing)
            }
        }
    }
}

@Test func modestTiltsProduceVisibleTravelWithin150Milliseconds() {
    for (degrees, minimumTravel) in [(1.0, 0.0035), (3.0, 0.01)] {
        for sign in [-1.0, 1.0] {
            var engine = TiltResponseFixture.engine()
            let start = engine.position
            let input = TiltResponse.apply(Vec2(sign * sin(degrees * Double.pi / 180), 0), sensitivity: 1.3)
            for _ in 0..<36 { _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: input) }
            let travel = (engine.position.x - start.x) * sign
            #expect(travel > minimumTravel,
                    "\(degrees)° must travel more than \(minimumTravel) board widths in 150 ms")
        }
    }
}

@Test func reversingTiltBrakesMomentumBeforeNaturallyReversingDirection() {
    let h = PhysicsEngine.fixedTimeStep
    for sign in [-1.0, 1.0] {
        var engine = TiltResponseFixture.engine()
        engine.velocity = Vec2(sign * 0.4, 0)
        let initialPosition = engine.position
        let input = TiltResponse.apply(Vec2(-sign * sin(3 * Double.pi / 180), 0), sensitivity: 1.3)
        _ = engine.step(dt: h, tilt: input)
        #expect(engine.velocity.x * sign > 0.35)
        #expect(engine.velocity.x * sign < 0.4)
        #expect((engine.position.x - initialPosition.x) * sign > 0,
                "Momentum must still advance the marble immediately after the input reverses")
        #expect(abs(engine.position.x - initialPosition.x) <= 0.4 * h + 1e-12)

        var reversalTime: Double?
        for step in 2...120 {
            let beforePosition = engine.position
            let beforeVelocity = engine.velocity
            _ = engine.step(dt: h, tilt: input)
            #expect(abs(engine.velocity.x - beforeVelocity.x) < 0.01,
                    "A small reversed tilt must not snap the velocity")
            let movementBound = max(abs(beforeVelocity.x), abs(engine.velocity.x)) * h
            #expect(abs(engine.position.x - beforePosition.x) <= movementBound + 1e-10,
                    "Reversing input must not teleport the marble")
            if engine.velocity.x * sign < 0 {
                reversalTime = Double(step) * h
                break
            }
        }
        #expect(reversalTime != nil)
        #expect((reversalTime ?? 1) < 0.5)
    }
}

@Test func returningToNeutralLetsTheMarbleCoast() {
    var engine = TiltResponseFixture.engine()
    engine.velocity = Vec2(0.4, 0)
    let start = engine.position
    let neutral = TiltResponse.apply(.zero, sensitivity: 1.3)
    _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: neutral)
    #expect(engine.velocity.x > 0.39)
    #expect(engine.velocity.x < 0.4)
    #expect(engine.position.x > start.x)
    for _ in 0..<11 { _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: neutral) }
    #expect(engine.velocity.x > 0.35,
            "Neutral input removes downhill acceleration without instantly removing momentum")
    #expect(engine.position.x - start.x > 0.015)
}

@Test func radialResponsePreservesDirectionOddnessAndIsotropy() {
    let magnitude = 0.04
    let baseline = TiltResponse.apply(Vec2(magnitude, 0), sensitivity: 1.3).length
    for angle in [0.0, Double.pi / 8, Double.pi / 4, Double.pi / 2, Double.pi, Double.pi * 1.75] {
        let raw = Vec2(cos(angle), sin(angle)) * magnitude
        let output = TiltResponse.apply(raw, sensitivity: 1.3)
        let opposite = TiltResponse.apply(-raw, sensitivity: 1.3)
        #expect(abs(output.length - baseline) < 1e-12)
        #expect(abs(output.x * raw.y - output.y * raw.x) < 1e-12)
        #expect(output.dot(raw) > 0)
        #expect(abs(output.x + opposite.x) < 1e-12)
        #expect(abs(output.y + opposite.y) < 1e-12)
    }
}

@Test func responseMagnitudeIncreasesMonotonicallyAndStaysBounded() {
    let direction = Vec2(0.6, -0.8)
    for sensitivity in [0.5, 1.0, 1.3, 2.5] {
        var previous = 0.0
        for magnitude in [0.0, 0.0001, 0.00046, 0.0006, 0.001, 0.003, 0.005, 0.01, 0.05, 0.1, 0.3, 0.6, 1.0] {
            let output = TiltResponse.apply(direction * magnitude, sensitivity: sensitivity)
            #expect(output.x.isFinite && output.y.isFinite)
            #expect(output.length >= previous - 1e-12)
            #expect(output.length <= 0.7 + 1e-12)
            previous = output.length
        }
    }
}

@Test func sensorNoiseIsQuietAndResponseHasNoInputHistory() {
    let noiseMagnitude = sin(0.02 * Double.pi / 180)
    for angle in [0.0, Double.pi / 4, Double.pi / 2, Double.pi, Double.pi * 1.75] {
        let noise = Vec2(cos(angle), sin(angle)) * noiseMagnitude
        #expect(TiltResponse.apply(noise, sensitivity: 1.3) == .zero)
    }
    let smallTilt = Vec2(sin(0.5 * Double.pi / 180), 0)
    let expected = TiltResponse.apply(smallTilt, sensitivity: 1.3)
    for raw in [Vec2(0.6, -0.4), Vec2(-0.5, 0.7), .zero, -smallTilt] {
        _ = TiltResponse.apply(raw, sensitivity: 1.3)
        #expect(TiltResponse.apply(smallTilt, sensitivity: 1.3) == expected)
    }
    #expect(TiltResponse.apply(.zero, sensitivity: 1.3) == .zero)
}

@Test func displayRateCannotChangeTheResponsiveMarbleTrajectory() {
    func run(displayRate: Int) -> PhysicsEngine {
        var engine = TiltResponseFixture.engine()
        let segments: [(Double, Vec2)] = [
            (0.15, Vec2(sin(Double.pi / 180), 0)),
            (0.10, Vec2(sin(3 * Double.pi / 180), sin(Double.pi / 180))),
            (0.10, .zero),
            (0.15, Vec2(-sin(3 * Double.pi / 180), -sin(Double.pi / 180)))
        ]
        for (duration, raw) in segments {
            for _ in 0..<Int((duration * Double(displayRate)).rounded()) {
                let input = TiltResponse.apply(raw, sensitivity: 1.3)
                _ = engine.step(dt: 1.0 / Double(displayRate), tilt: input)
            }
        }
        return engine
    }
    let sixty = run(displayRate: 60)
    let oneTwenty = run(displayRate: 120)
    #expect(sixty.position.distance(to: oneTwenty.position) < 1e-12)
    #expect(sixty.velocity.distance(to: oneTwenty.velocity) < 1e-12)
    #expect(abs(sixty.elapsed - oneTwenty.elapsed) < 1e-12)
    #expect(sixty.status == .playing && oneTwenty.status == .playing)
}

@Test func invalidInputsAndSensitivityCannotProduceNonfiniteMovement() {
    let inputs = [Vec2(Double.nan, 0.1), Vec2(0.2, Double.infinity),
                  Vec2(-Double.infinity, Double.nan), .zero, Vec2(0.1, -0.2),
                  Vec2(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)]
    for sensitivity in [Double.nan, Double.infinity, -Double.infinity, -1, 0, 1.3, Double.greatestFiniteMagnitude] {
        for raw in inputs {
            let output = TiltResponse.apply(raw, sensitivity: sensitivity)
            #expect(output.x.isFinite && output.y.isFinite)
            #expect(output.length <= 0.7 + 1e-12)
        }
    }
}

@Test func counterTiltMeaningfullyShortensBuildTwoStoppingTimeAndDistance() {
    for degrees in [1.0, 3.0, 5.0] {
        let response = TiltResponse.apply(Vec2(sin(degrees * Double.pi / 180), 0), sensitivity: 1.3)
        let baseline = TiltResponseFixture.buildTwoBrakingReference(tilt: response.x)
        for sign in [-1.0, 1.0] {
            var engine = TiltResponseFixture.engine()
            engine.velocity = Vec2(sign * 0.4, 0)
            let start = engine.position.x
            var maximumTravel = 0.0
            var stoppingTime: Double?
            for step in 1...240 {
                _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: response * -sign)
                maximumTravel = max(maximumTravel, (engine.position.x - start) * sign)
                if engine.velocity.x * sign <= 0 {
                    stoppingTime = Double(step) * PhysicsEngine.fixedTimeStep
                    break
                }
            }
            #expect(stoppingTime != nil)
            #expect((stoppingTime ?? 1) > 0.05, "Counter-tilt must brake continuously, rather than snap to rest")
            #expect((stoppingTime ?? 1) < baseline.time * 0.85)
            #expect(maximumTravel > 0)
            #expect(maximumTravel < baseline.distance * 0.80,
                    "\(degrees)° counter-tilt must reduce the old slippery stopping distance by at least 20 percent")
            if degrees == 3 {
                #expect((stoppingTime ?? 1) < 0.28)
                #expect(maximumTravel < 0.045)
            }
        }
    }
}

@Test func counterTiltPreservesForwardStartsAndNeutralCoasting() {
    for degrees in [0.25, 0.5, 1.0, 3.0] {
        let input = TiltResponse.apply(Vec2(sin(degrees * Double.pi / 180), 0), sensitivity: 1.3)
        for steps in [1, 36] {
            var engine = TiltResponseFixture.engine()
            let start = engine.position.x
            for _ in 0..<steps { _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: input) }
            let reference = TiltResponseFixture.buildTwoForwardReference(tilt: input.x, velocity: 0, steps: steps)
            #expect(abs(engine.velocity.x - reference.velocity) < 1e-10)
            #expect(abs(engine.position.x - start - reference.distance) < 1e-10,
                    "Braking assistance must leave first-step and 150 ms forward response unchanged")
        }
    }
    var coasting = TiltResponseFixture.engine()
    coasting.velocity = Vec2(0.4, 0)
    let start = coasting.position.x
    for _ in 0..<36 { _ = coasting.step(dt: PhysicsEngine.fixedTimeStep, tilt: .zero) }
    let reference = TiltResponseFixture.buildTwoForwardReference(tilt: 0, velocity: 0.4, steps: 36)
    #expect(abs(coasting.velocity.x - reference.velocity) < 1e-10)
    #expect(abs(coasting.position.x - start - reference.distance) < 1e-10)
}

@Test func counterTiltLeavesPerpendicularMomentumUndamped() {
    var engine = TiltResponseFixture.engine()
    engine.velocity = Vec2(0.4, 0.2)
    let input = TiltResponse.apply(Vec2(-sin(3 * Double.pi / 180), 0), sensitivity: 1.3)
    for _ in 0..<12 { _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: input) }
    #expect(engine.velocity.x < 0.32, "The opposed X component should brake promptly")
    #expect(engine.velocity.y > 0.194,
            "Braking X must preserve Y momentum apart from the existing light drag and rolling resistance")
    #expect(engine.velocity.y < 0.2)
}

@Test func counterTiltEffectVanishesContinuouslyNearRest() {
    let epsilon = 1e-6
    let input = TiltResponse.apply(Vec2(-sin(3 * Double.pi / 180), 0), sensitivity: 1.3)
    func nextVelocity(_ velocity: Double) -> Double {
        var engine = TiltResponseFixture.engine()
        engine.velocity = Vec2(velocity, 0)
        _ = engine.step(dt: PhysicsEngine.fixedTimeStep, tilt: input)
        return engine.velocity.x
    }
    let resting = nextVelocity(0)
    let opposing = nextVelocity(epsilon)
    let following = nextVelocity(-epsilon)
    #expect(resting < 0 && opposing < 0 && following < 0)
    #expect(opposing - resting > epsilon * 0.9)
    #expect(opposing - resting < epsilon)
    #expect(resting - following > epsilon * 0.9)
    #expect(resting - following < epsilon)
    #expect(abs((opposing + following) * 0.5 - resting) < epsilon * 0.015,
            "There must be no finite braking force or velocity snap at the resting threshold")
}

@Test func counterTiltBrakingMatchesAt60And120DisplayRates() {
    let input = TiltResponse.apply(Vec2(-sin(3 * Double.pi / 180), 0), sensitivity: 1.3)
    func run(_ displayRate: Int) -> PhysicsEngine {
        var engine = TiltResponseFixture.engine()
        engine.velocity = Vec2(0.4, 0.2)
        for _ in 0..<(displayRate / 2) { _ = engine.step(dt: 1.0 / Double(displayRate), tilt: input) }
        return engine
    }
    let sixty = run(60)
    let oneTwenty = run(120)
    #expect(sixty.velocity.x < 0 && oneTwenty.velocity.x < 0)
    #expect(sixty.position.distance(to: oneTwenty.position) < 1e-12)
    #expect(sixty.velocity.distance(to: oneTwenty.velocity) < 1e-12)
    #expect(abs(sixty.elapsed - oneTwenty.elapsed) < 1e-12)
}

private enum TiltResponseFixture {
    static func engine() -> PhysicsEngine {
        let level = MazeLevel(id: "tilt-response-empty", title: "Response fixture",
                              start: Vec2(0.5, 0.7), goal: Vec2(0.9, 1.2))
        var engine = PhysicsEngine(level: level)
        engine.start()
        return engine
    }

    /// Frozen build-two dynamics, independently integrated with RK4 at eight times
    /// the simulation frequency. It contains no direction-specific braking term.
    static func buildTwoBrakingReference(tilt: Double) -> (time: Double, distance: Double) {
        let h = 1.0 / 1_920
        let downhill = 4.905 * tilt + 0.008
        func rate(_ velocity: Double) -> Double { -downhill - 0.5 * velocity }
        var velocity = 0.4
        var distance = 0.0
        for step in 0..<3_840 {
            let k1 = rate(velocity)
            let k2 = rate(velocity + k1 * h * 0.5)
            let k3 = rate(velocity + k2 * h * 0.5)
            let k4 = rate(velocity + k3 * h)
            let next = velocity + h * (k1 + 2 * k2 + 2 * k3 + k4) / 6
            if next <= 0 {
                let fraction = velocity / (velocity - next)
                return (Double(step) * h + fraction * h, distance + velocity * fraction * h * 0.5)
            }
            distance += (velocity + next) * h * 0.5
            velocity = next
        }
        return (2, distance)
    }

    /// Closed-form samples of the old gravity/drag/resistance ODE, summed at the
    /// board's fixed integration times. Valid here while forward velocity stays positive.
    static func buildTwoForwardReference(tilt: Double, velocity: Double, steps: Int) -> (velocity: Double, distance: Double) {
        let h = PhysicsEngine.fixedTimeStep
        let decay = exp(-0.5 * h)
        let endDecay = pow(decay, Double(steps))
        let equilibrium = (4.905 * tilt - 0.008) / 0.5
        let finalVelocity = equilibrium + (velocity - equilibrium) * endDecay
        let sumDecay = decay * (1 - endDecay) / (1 - decay)
        let distance = h * (Double(steps) * equilibrium + (velocity - equilibrium) * sumDecay)
        return (finalVelocity, distance)
    }
}
