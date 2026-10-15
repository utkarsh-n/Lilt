import Foundation
import Testing
@testable import LiltCore

@Test func descriptionsChangeBoardsAndHonorNegation() throws {
    let recipe = RecipeParser.parse("An easy jade spiral with three holes, two bumpers and one magnet, no fans")
    #expect(recipe.difficulty == .easy)
    #expect(recipe.theme == .jade)
    #expect(recipe.style == .spiral)
    #expect(recipe.holeCount == 3)
    #expect(recipe.bumperCount == 2)
    #expect(recipe.magnetCount == 1)
    #expect(recipe.fanCount == 0)
    #expect(RecipeParser.parse("A hard midnight pinball board without holes with two magnets").holeCount == 0)
    #expect(RecipeParser.parse("No holes or magnets, but three bumpers").magnetCount == 0)
    #expect(RecipeParser.parse("A hole-free garden without bumpers, magnets or fans").bumperCount == 0)
    #expect(RecipeParser.parse("A hole-free garden without bumpers, magnets or fans").fanCount == 0)
    #expect(RecipeParser.parse("no holes, four bumpers").holeCount == 0)
    #expect(RecipeParser.parse("no holes, four bumpers").bumperCount == 4)
    #expect(RecipeParser.parse("4 bumpers and no holes").bumperCount == 4)
    #expect(RecipeParser.parse("4 bumpers and no holes").holeCount == 0)
    #expect(RecipeParser.parse("two holes and bumpers").holeCount == 2)
    #expect(RecipeParser.parse("two holes and bumpers").bumperCount == 3)
    #expect(RecipeParser.parse("no holes or bumpers").bumperCount == 0)
    #expect(RecipeParser.parse("no holes. Four bumpers").bumperCount == 4)
    #expect(RecipeParser.parse("one magnetic magnet").magnetCount == 1)
    let modelRecipe = MazeRecipe(holeCount: 8, bumperCount: 9, magnetCount: 4, fanCount: 3)
    let constrained = RecipeParser.enforcingExplicitCounts(in: "no holes, four bumpers and magnets", on: modelRecipe)
    #expect(constrained.holeCount == 0)
    #expect(constrained.bumperCount == 4)
    #expect(constrained.magnetCount == 4)
    #expect(constrained.fanCount == 3)
    let gentle = try MazeGenerator.generate(recipe: RecipeParser.parse("An easy oak garden, no holes"), seed: 42)
    let precise = try MazeGenerator.generate(recipe: RecipeParser.parse("A hard midnight spiral, nine holes"), seed: 42)
    #expect(gentle.holes.isEmpty)
    #expect(gentle.walls != precise.walls)
    #expect(gentle.ballRadius > precise.ballRadius)
    #expect(precise.theme == .midnight)
}

@Test func generationAndCodablePersistenceAreReproducible() throws {
    let recipe = RecipeParser.parse("A medium garden with four holes, two bumpers, one magnet and one fan")
    let seed = RecipeParser.seed(for: recipe.description)
    let first = try MazeGenerator.generate(recipe: recipe, seed: seed)
    let second = try MazeGenerator.generate(recipe: recipe, seed: seed)
    let otherSeed = try MazeGenerator.generate(recipe: recipe, seed: seed &+ 1)
    #expect(first == second)
    #expect(first.walls != otherSeed.walls)
    #expect(first.holes.count == 4)
    #expect(first.features.filter { $0.kind == .bumper }.count == 2)
    #expect(first.features.filter { $0.kind == .magnet }.count == 1)
    #expect(first.features.filter { $0.kind == .fan }.count == 1)
    let data = try JSONEncoder().encode(first)
    #expect(try JSONDecoder().decode(MazeLevel.self, from: data) == first)
}

@Test func explicitPreferencesOverrideOnlyDocumentedPositiveChoices() {
    let model = MazeRecipe(description: "Model interpretation", difficulty: .hard, theme: .midnight,
                           style: .pinball, holeCount: 9, bumperCount: 4, magnetCount: 2, fanCount: 1)
    let description = "A tricky wooden spiral with five holes, winding toward the center."
    let constrained = RecipeParser.enforcingExplicitPreferences(in: description, on: model)
    #expect(constrained.difficulty == .medium)
    #expect(constrained.theme == .oak)
    #expect(constrained.style == .spiral)
    #expect(constrained.holeCount == model.holeCount)
    #expect(constrained.bumperCount == model.bumperCount)
    #expect(RecipeParser.enforcingExplicitCounts(in: description, on: constrained).holeCount == 5)
    for word in ["tricky", "medium", "moderate"] { #expect(RecipeParser.parse("A \(word) labyrinth").difficulty == .medium) }
    #expect(RecipeParser.enforcingExplicitPreferences(in: "A gentle wide maple garden", on: model).difficulty == .easy)
    #expect(RecipeParser.enforcingExplicitPreferences(in: "A gentle wide maple garden", on: model).theme == .jade)
    #expect(RecipeParser.enforcingExplicitPreferences(in: "Expert narrow oak pinball", on: MazeRecipe()).difficulty == .hard)
    #expect(RecipeParser.enforcingExplicitPreferences(in: "Maple at night", on: MazeRecipe()).theme == .midnight)
    #expect(RecipeParser.enforcingExplicitPreferences(in: "A meditative slate meander", on: model) == model)
    #expect(RecipeParser.enforcingExplicitPreferences(in: "No spiral", on: model) == model)
}

@Test func generatedRoutesHaveContinuousBallClearance() throws {
    for difficulty in MazeDifficulty.allCases {
        for style in MazeStyle.allCases {
            for seed in UInt64(0)..<12 {
                let recipe = MazeRecipe(difficulty: difficulty, style: style, holeCount: 8,
                                        bumperCount: 3, magnetCount: 2, fanCount: 2)
                let level = try MazeGenerator.generate(recipe: recipe, seed: seed)
                try MazeValidator.validate(level)
                #expect(level.holes.count == 8)
                #expect(level.features.filter { $0.kind == .bumper }.count == 3)
                #expect(level.features.filter { $0.kind == .magnet }.count == 2)
                #expect(level.features.filter { $0.kind == .fan }.count == 2)
                for (a, b) in zip(level.solution, level.solution.dropFirst()) {
                    for wall in level.walls {
                        #expect(Geometry.segmentDistance(a, b, wall.a, wall.b) + 1e-8 >= level.ballRadius + wall.thickness * 0.5)
                    }
                }
            }
        }
    }
}

@Test func independentFloodFillCanReachEveryStyleAndCampaignGoal() throws {
    for difficulty in MazeDifficulty.allCases {
        for style in MazeStyle.allCases {
            let level = try MazeGenerator.generate(recipe: MazeRecipe(difficulty: difficulty, style: style,
                                                                      holeCount: 8, bumperCount: 3), seed: 0xA55A)
            #expect(reachableByBall(level), "\(difficulty) \(style) must admit a full-size ball")
        }
    }
    #expect(Campaign.levels.count == 12)
    #expect(Set(Campaign.levels.map(\.id)).count == Campaign.levels.count)
    for level in Campaign.levels {
        try MazeValidator.validate(level)
        #expect(reachableByBall(level), "\(level.title) must admit a full-size ball")
    }
    #expect(Campaign.levels.contains { $0.features.contains { $0.kind == .bumper } })
    #expect(Campaign.levels.contains { $0.features.contains { $0.kind == .magnet } })
    #expect(Campaign.levels.contains { $0.features.contains { $0.kind == .fan } })
}

@Test func physicalBallCanFollowGeneratedAndAuthoredRoutes() throws {
    var levels = Array(Campaign.levels.prefix(4))
    levels.append(try MazeGenerator.generate(recipe: MazeRecipe(difficulty: .easy, style: .switchbacks, holeCount: 4), seed: 91))
    levels.append(try MazeGenerator.generate(recipe: MazeRecipe(difficulty: .medium, style: .spiral, holeCount: 6), seed: 92))
    levels.append(try MazeGenerator.generate(recipe: MazeRecipe(difficulty: .hard, style: .garden, holeCount: 8,
                                                               bumperCount: 2, magnetCount: 2, fanCount: 2), seed: 93))
    for level in levels {
        var engine = PhysicsEngine(level: level)
        engine.start()
        var waypoint = 1
        for _ in 0..<18_000 where engine.status == .playing {
            let destination = level.solution[waypoint]
            let delta = destination - engine.position
            if delta.length < 0.007, waypoint + 1 < level.solution.count { waypoint += 1 }
            let error = level.solution[waypoint] - engine.position
            var desiredVelocity = error * 4.0
            if desiredVelocity.length > 0.32 { desiredVelocity = desiredVelocity.normalized * 0.32 }
            let resistance = engine.velocity * PhysicsEngine.viscousDrag
                + desiredVelocity.normalized * PhysicsEngine.rollingFriction
            var tilt = ((desiredVelocity - engine.velocity) * 8.0 + resistance) / PhysicsEngine.rollingGravity
            if tilt.length > 0.8 { tilt = tilt.normalized * 0.8 }
            _ = engine.step(dt: 1.0 / 60, tilt: tilt)
        }
        #expect(engine.status == .won, "\(level.title): ended \(engine.status) at \(engine.position), waypoint \(waypoint)")
    }
}

@Test func stationaryBallHasNoAutomaticMovementAndTiltAcceleratesIt() {
    var engine = PhysicsEngine(level: emptyLevel())
    engine.start()
    for _ in 0..<60 { _ = engine.step(dt: 1.0 / 60, tilt: .zero) }
    #expect(engine.position == engine.level.start)
    #expect(engine.velocity == .zero)
    _ = engine.step(dt: 0.1, tilt: Vec2(0.2, 0))
    #expect(engine.velocity.x > 0)
    #expect(engine.position.x > engine.level.start.x)
    #expect(abs(engine.position.y - engine.level.start.y) < 1e-12)
}

@Test func displayRateDoesNotChangeSimulation() {
    var sixty = PhysicsEngine(level: emptyLevel())
    var oneTwenty = PhysicsEngine(level: emptyLevel())
    sixty.start(); oneTwenty.start()
    for _ in 0..<60 { _ = sixty.step(dt: 1.0 / 60, tilt: Vec2(0.08, -0.04)) }
    for _ in 0..<120 { _ = oneTwenty.step(dt: 1.0 / 120, tilt: Vec2(0.08, -0.04)) }
    #expect(sixty.position.distance(to: oneTwenty.position) < 1e-12)
    #expect(sixty.velocity.distance(to: oneTwenty.velocity) < 1e-12)
    #expect(abs(sixty.elapsed - 1) < 1e-10)
    #expect(abs(sixty.elapsed - oneTwenty.elapsed) < 1e-12)
}

@Test func neutralMarbleCoastsToAnExactFiniteStop() {
    var level = emptyLevel()
    level.width = 2
    level.goal = Vec2(1.7, 1.2)
    var engine = PhysicsEngine(level: level)
    engine.velocity = Vec2(0.4, 0)
    engine.start()
    var stoppedAt: Double?
    for frame in 1...1_200 {
        _ = engine.step(dt: 1.0 / 120, tilt: .zero)
        if frame == 18 {
            // Leveling the board must preserve forward momentum, rather than turn
            // the marble into a position-controlled cursor.
            #expect(engine.velocity.x > 0.32)
            #expect(engine.position.x > level.start.x + 0.05)
        }
        if engine.velocity == .zero, stoppedAt == nil { stoppedAt = Double(frame) / 120 }
    }
    #expect(stoppedAt != nil)
    #expect(stoppedAt.map { $0 > 2 && $0 < 9 } == true)
    let travel = engine.position.x - engine.level.start.x
    #expect(travel > 0.3 && travel < 0.9)
    let restingPosition = engine.position
    for _ in 0..<120 { _ = engine.step(dt: 1.0 / 120, tilt: .zero) }
    #expect(engine.velocity == .zero)
    #expect(engine.position == restingPosition)
}

@Test func subNoiseTiltRestsAndOneDegreeStartsARoll() {
    var engine = PhysicsEngine(level: emptyLevel())
    engine.start()
    let pointZeroTwoDegrees = sin(0.02 * Double.pi / 180) * 1.3
    for _ in 0..<120 { _ = engine.step(dt: 1.0 / 120, tilt: Vec2(pointZeroTwoDegrees, 0)) }
    #expect(engine.velocity == .zero)
    #expect(engine.position == engine.level.start)
    let oneDegree = sin(Double.pi / 180) * 1.3
    for _ in 0..<120 { _ = engine.step(dt: 1.0 / 120, tilt: Vec2(oneDegree, 0)) }
    #expect(engine.velocity.x > 0.03 && engine.velocity.x < 0.15)
    let travel = engine.position.x - engine.level.start.x
    #expect(travel > 0.02 && travel < 0.08)
}

@Test func oppositeTiltBrakesThenNaturallyReversesTheMarble() {
    var engine = PhysicsEngine(level: emptyLevel())
    engine.velocity = Vec2(0.4, 0)
    engine.start()
    let oppositeTenDegrees = -sin(10 * Double.pi / 180) * 1.3
    var brakeTime = 0.0
    for frame in 1...120 {
        _ = engine.step(dt: 1.0 / 240, tilt: Vec2(oppositeTenDegrees, 0))
        if engine.velocity.x <= 0 { brakeTime = Double(frame) / 240; break }
    }
    #expect(brakeTime > 0 && brakeTime <= 0.4)
    let brakingDistance = engine.position.x - engine.level.start.x
    #expect(brakingDistance > 0 && brakingDistance < 0.15)
    for _ in 0..<48 { _ = engine.step(dt: 1.0 / 240, tilt: Vec2(oppositeTenDegrees, 0)) }
    #expect(engine.velocity.x < -0.05)
}

@Test func fastBallCannotTunnelThroughWallsOrRoundedEnds() {
    var level = emptyLevel()
    level.walls = [MazeWall(a: Vec2(0.50, 0.05), b: Vec2(0.50, 1.4), thickness: 0.02)]
    var engine = PhysicsEngine(level: level)
    engine.position = Vec2(0.20, 0.7); engine.velocity = Vec2(40, 0); engine.start()
    let events = engine.step(dt: 1.0 / 60, tilt: .zero)
    #expect(engine.position.x <= 0.5 - level.ballRadius - 0.01 + 1e-7)
    #expect(engine.velocity.x < 0)
    #expect(events.contains { if case .impact = $0 { true } else { false } })

    let wall = MazeWall(a: Vec2(0.50, 0.70), b: Vec2(0.50, 1.0), thickness: 0.02)
    level.walls = [wall]
    var endpoint = PhysicsEngine(level: level)
    endpoint.position = Vec2(0.20, 0.69); endpoint.velocity = Vec2(40, 0); endpoint.start()
    _ = endpoint.step(dt: 1.0 / 60, tilt: .zero)
    #expect(endpoint.position.x < 0.50)
    #expect(Geometry.pointSegmentDistance(endpoint.position, wall.a, wall.b) >= level.ballRadius + wall.thickness * 0.5 - 1e-7)
}

@Test func fastHoleCaptureFallsOnceAndRestartRestoresState() {
    var level = emptyLevel()
    level.holes = [MazeHole(center: Vec2(0.50, 0.70), radius: 0.04)]
    var engine = PhysicsEngine(level: level)
    engine.position = Vec2(0.20, 0.70); engine.velocity = Vec2(35, 0); engine.start()
    let events = engine.step(dt: 1.0 / 60, tilt: .zero)
    #expect(events.filter { $0 == .fell }.count == 1)
    #expect(engine.status == .falling)
    let later = engine.step(dt: 0.25, tilt: Vec2(1, 1)) + engine.step(dt: 0.25, tilt: Vec2(1, 1))
    #expect(later.isEmpty)
    #expect(engine.fallProgress == 1)
    #expect(engine.position.distance(to: level.holes[0].center) < 0.001)
    engine.reset()
    #expect(engine.status == .ready)
    #expect(engine.position == level.start)
    #expect(engine.velocity == .zero)
    #expect(engine.elapsed == 0)
    #expect(engine.fallProgress == 0)
    #expect(engine.step(dt: 0.1, tilt: Vec2(1, 0)).isEmpty)
    #expect(engine.position == level.start)
}

@Test func fastGoalCaptureWinsOnce() {
    var level = emptyLevel(); level.goal = Vec2(0.50, 0.70)
    var engine = PhysicsEngine(level: level)
    engine.position = Vec2(0.20, 0.70); engine.velocity = Vec2(35, 0); engine.start()
    #expect(engine.step(dt: 1.0 / 60, tilt: .zero).contains(.won))
    #expect(engine.status == .won)
    #expect(engine.position == level.goal)
    #expect(engine.step(dt: 0.1, tilt: Vec2(1, 0)).isEmpty)
}

@Test func bumpersReboundAndFieldsApplyPhysicalForces() {
    var level = emptyLevel()
    level.features = [MazeFeature(kind: .bumper, center: Vec2(0.50, 0.70), radius: 0.045)]
    var bumper = PhysicsEngine(level: level)
    bumper.position = Vec2(0.20, 0.70); bumper.velocity = Vec2(2, 0); bumper.start()
    _ = bumper.step(dt: 0.2, tilt: .zero)
    #expect(bumper.velocity.x < -1)
    #expect(bumper.position.x < 0.50)
    level.features = [MazeFeature(kind: .magnet, center: Vec2(0.40, 0.70), radius: 0.04)]
    var magnet = PhysicsEngine(level: level)
    magnet.position = Vec2(0.30, 0.70); magnet.start()
    _ = magnet.step(dt: 0.1, tilt: .zero)
    #expect(magnet.velocity.x > 0)
    level.features = [MazeFeature(kind: .fan, center: Vec2(0.30, 0.70), radius: 0.04, direction: Vec2(0, -1))]
    var fan = PhysicsEngine(level: level)
    fan.position = Vec2(0.30, 0.70); fan.start()
    _ = fan.step(dt: 0.1, tilt: .zero)
    #expect(fan.velocity.y < 0)
}

@Test func validatorRejectsAConnectedLineWithoutBallClearance() {
    var level = emptyLevel()
    level.start = Vec2(0.2, 0.7); level.goal = Vec2(0.8, 0.7)
    level.solution = [level.start, level.goal]
    level.walls = [MazeWall(a: Vec2(0.5, 0.05), b: Vec2(0.5, 1.4), thickness: 0.02)]
    #expect(throws: MazeGenerationError.blockedSolution) { try MazeValidator.validate(level) }
}

private func emptyLevel() -> MazeLevel {
    MazeLevel(id: "test", title: "Test", start: Vec2(0.25, 0.70), goal: Vec2(0.85, 1.25), ballRadius: 0.025)
}

/// Independent raster reachability using inflated obstacle geometry, with no use of the
/// generator's passage graph or its stored solution. Grid spacing is less than half a radius.
private func reachableByBall(_ level: MazeLevel) -> Bool {
    let spacing = level.ballRadius * 0.45
    let columns = Int(ceil(level.width / spacing)) + 1
    let rows = Int(ceil(level.height / spacing)) + 1
    var walkable = Array(repeating: false, count: columns * rows)
    for row in 0..<rows {
        for column in 0..<columns {
            let point = Vec2(Double(column) * spacing, Double(row) * spacing)
            guard point.x >= level.ballRadius, point.x <= level.width - level.ballRadius,
                  point.y >= level.ballRadius, point.y <= level.height - level.ballRadius else { continue }
            if level.walls.contains(where: { Geometry.pointSegmentDistance(point, $0.a, $0.b) < level.ballRadius + $0.thickness * 0.5 }) { continue }
            if level.holes.contains(where: { point.distance(to: $0.center) < level.ballRadius * 0.8 + $0.radius }) { continue }
            if level.features.contains(where: { $0.kind == .bumper && point.distance(to: $0.center) < level.ballRadius + $0.radius }) { continue }
            walkable[row * columns + column] = true
        }
    }
    func index(_ point: Vec2) -> Int {
        Int((point.y / spacing).rounded()) * columns + Int((point.x / spacing).rounded())
    }
    let start = index(level.start), goal = index(level.goal)
    guard walkable[start], walkable[goal] else { return false }
    var visited = Array(repeating: false, count: walkable.count)
    var queue = [start]; visited[start] = true
    var head = 0
    while head < queue.count {
        let current = queue[head]; head += 1
        if current == goal { return true }
        let column = current % columns, row = current / columns
        var neighbors: [Int] = []
        if column > 0 { neighbors.append(current - 1) }
        if column + 1 < columns { neighbors.append(current + 1) }
        if row > 0 { neighbors.append(current - columns) }
        if row + 1 < rows { neighbors.append(current + columns) }
        for next in neighbors where walkable[next] && !visited[next] { visited[next] = true; queue.append(next) }
    }
    return false
}
