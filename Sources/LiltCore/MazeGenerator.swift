import Foundation

public enum MazeGenerationError: Error, Sendable, Equatable, LocalizedError {
    case invalidDimensions
    case invalidGeometry
    case blockedSolution
    case unreachableGoal

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: "The board dimensions or ball size are invalid."
        case .invalidGeometry: "The labyrinth contains invalid geometry."
        case .blockedSolution: "The labyrinth has insufficient clearance along its route."
        case .unreachableGoal: "The goal cannot be reached by the ball."
        }
    }
}

public enum MazeGenerator {
    public static func generate(recipe: MazeRecipe, seed: UInt64) throws -> MazeLevel {
        var random = SplitMix64(seed: seed)
        let columns = recipe.difficulty == .easy ? 5 : recipe.difficulty == .medium ? 6 : 8
        let rows = recipe.difficulty == .easy ? 7 : recipe.difficulty == .medium ? 9 : 11
        let width = 1.0, height = 1.45, inset = 0.035
        let cellWidth = (width - inset * 2) / Double(columns)
        let cellHeight = (height - inset * 2) / Double(rows)
        let radius = recipe.difficulty == .easy ? 0.025 : recipe.difficulty == .medium ? 0.022 : 0.0185
        let thickness = recipe.difficulty == .hard ? 0.016 : 0.02
        let count = columns * rows
        func center(_ cell: Int) -> Vec2 {
            Vec2(inset + (Double(cell % columns) + 0.5) * cellWidth,
                 inset + (Double(cell / columns) + 0.5) * cellHeight)
        }
        func neighbors(_ cell: Int) -> [Int] {
            let x = cell % columns, y = cell / columns
            var output: [Int] = []
            if y > 0 { output.append(cell - columns) }
            if x + 1 < columns { output.append(cell + 1) }
            if y + 1 < rows { output.append(cell + columns) }
            if x > 0 { output.append(cell - 1) }
            return output
        }

        var passages = Set<Edge>()
        var preferred: [Int] = []
        switch recipe.style {
        case .switchbacks:
            // A long horizontal rhythm with occasional branches created below.
            for row in (0..<rows).reversed() {
                let forward = (rows - 1 - row).isMultiple(of: 2)
                let xs = forward ? Array(0..<columns) : Array((0..<columns).reversed())
                preferred += xs.map { row * columns + $0 }
            }
        case .spiral:
            // Spiral traversal visits every grid cell exactly once.
            var left = 0, right = columns - 1, top = 0, bottom = rows - 1
            while left <= right && top <= bottom {
                for y in stride(from: bottom, through: top, by: -1) { preferred.append(y * columns + left) }
                left += 1
                if left <= right { for x in left...right { preferred.append(top * columns + x) } }
                top += 1
                if top <= bottom && left <= right {
                    for y in top...bottom { preferred.append(y * columns + right) }
                    right -= 1
                }
                if left <= right && top <= bottom {
                    for x in stride(from: right, through: left, by: -1) { preferred.append(bottom * columns + x) }
                    bottom -= 1
                }
            }
        case .garden, .pinball: break
        }

        if !preferred.isEmpty {
            // Keep most of the authored rhythm, then complete a spanning tree. A small
            // number of omitted edges gives descriptions with the same style unique forks.
            var disjoint = DisjointSet(count: count)
            for pair in zip(preferred, preferred.dropFirst()) {
                if random.unit() > 0.16 && disjoint.join(pair.0, pair.1) { passages.insert(Edge(pair.0, pair.1)) }
            }
            var candidates: [Edge] = []
            for cell in 0..<count {
                for neighbor in neighbors(cell) where neighbor > cell { candidates.append(Edge(cell, neighbor)) }
            }
            random.shuffle(&candidates)
            for edge in candidates where disjoint.join(edge.a, edge.b) { passages.insert(edge) }
        } else {
            // Randomized Prim-like growth makes a branching garden instead of a corridor.
            var visited: Set<Int> = [0]
            var frontier = neighbors(0).map { Edge(0, $0) }
            while !frontier.isEmpty {
                let index = random.index(frontier.count)
                let edge = frontier.remove(at: index)
                let aVisited = visited.contains(edge.a), bVisited = visited.contains(edge.b)
                guard aVisited != bVisited else { continue }
                let next = aVisited ? edge.b : edge.a
                passages.insert(edge); visited.insert(next)
                for neighbor in neighbors(next) where !visited.contains(neighbor) { frontier.append(Edge(next, neighbor)) }
            }
        }

        if recipe.style == .garden || recipe.style == .pinball {
            // Loops and wider courts leave space for wind, fields, and ricochets.
            let extraChance = recipe.style == .garden ? 0.24 : 0.38
            for cell in 0..<count {
                for neighbor in neighbors(cell) where neighbor > cell && random.unit() < extraChance {
                    passages.insert(Edge(cell, neighbor))
                }
            }
        }

        let startCell = (rows - 1) * columns
        let goalCell = recipe.style == .spiral ? (preferred.last ?? columns - 1) : columns - 1
        func route(through connections: Set<Edge>) -> [Int] {
            var parents = Array(repeating: -1, count: count)
            var queue = [startCell]; parents[startCell] = startCell
            var head = 0
            while head < queue.count {
                let current = queue[head]; head += 1
                if current == goalCell { break }
                for neighbor in neighbors(current) where parents[neighbor] == -1 && connections.contains(Edge(current, neighbor)) {
                    parents[neighbor] = current; queue.append(neighbor)
                }
            }
            guard parents[goalCell] != -1 else { return [] }
            var path = [goalCell]
            while path.last! != startCell { path.append(parents[path.last!]) }
            return Array(path.reversed())
        }
        var pathCells = route(through: passages)
        guard !pathCells.isEmpty else { throw MazeGenerationError.unreachableGoal }

        // Reserve actual side rooms for the requested objects. A near-Hamiltonian snake
        // can otherwise consume every cell and silently discard "three holes". Add the
        // smallest useful shortcuts until the protected route leaves enough safe rooms.
        let requestedObjects = min(24, max(0, recipe.holeCount)) + min(18, max(0, recipe.bumperCount))
            + min(8, max(0, recipe.magnetCount)) + min(8, max(0, recipe.fanCount))
        var possibleShortcuts: [Edge] = []
        for cell in 0..<count {
            for neighbor in neighbors(cell) where neighbor > cell {
                let edge = Edge(cell, neighbor)
                if !passages.contains(edge) { possibleShortcuts.append(edge) }
            }
        }
        random.shuffle(&possibleShortcuts)
        while count - pathCells.count < requestedObjects {
            var choice: Edge?
            var chosenRoute: [Int] = []
            for edge in possibleShortcuts where !passages.contains(edge) {
                var proposed = passages; proposed.insert(edge)
                let candidateRoute = route(through: proposed)
                if !candidateRoute.isEmpty, candidateRoute.count < pathCells.count,
                   choice == nil || candidateRoute.count > chosenRoute.count {
                    choice = edge; chosenRoute = candidateRoute
                }
            }
            guard let choice else { break }
            passages.insert(choice); pathCells = chosenRoute
        }
        var solution = pathCells.map(center)

        // Keep every grid center in the underlying route for validation, but expose only
        // its corners. Straight pieces render cleanly and make hints easier to follow.
        if solution.count > 2 {
            var corners = [solution[0]]
            for index in 1..<(solution.count - 1) {
                let previous = solution[index] - solution[index - 1]
                let next = solution[index + 1] - solution[index]
                if abs(previous.x * next.y - previous.y * next.x) > 1e-10 { corners.append(solution[index]) }
            }
            corners.append(solution.last!); solution = corners
        }

        var walls = perimeter(width: width, height: height, inset: inset, thickness: thickness)
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = row * columns + column
                let x = inset + Double(column) * cellWidth, y = inset + Double(row) * cellHeight
                if column + 1 < columns, !passages.contains(Edge(cell, cell + 1)) {
                    walls.append(MazeWall(a: Vec2(x + cellWidth, y), b: Vec2(x + cellWidth, y + cellHeight), thickness: thickness))
                }
                if row + 1 < rows, !passages.contains(Edge(cell, cell + columns)) {
                    walls.append(MazeWall(a: Vec2(x, y + cellHeight), b: Vec2(x + cellWidth, y + cellHeight), thickness: thickness))
                }
            }
        }
        walls = mergeCollinear(walls)

        let safeDistance = radius + 0.014
        var candidates = (0..<count).filter { !pathCells.contains($0) }.map(center)
        random.shuffle(&candidates)
        var holes: [MazeHole] = []
        var features: [MazeFeature] = []
        func nearRoute(_ point: Vec2, clearance: Double) -> Bool {
            zip(solution, solution.dropFirst()).contains { Geometry.pointSegmentDistance(point, $0.0, $0.1) < clearance }
        }
        func available(_ point: Vec2, footprint: Double) -> Bool {
            !nearRoute(point, clearance: footprint + safeDistance)
            && !walls.contains { Geometry.pointSegmentDistance(point, $0.a, $0.b) < footprint + $0.thickness * 0.5 + 0.006 }
            && !holes.contains { point.distance(to: $0.center) < footprint + $0.radius + radius * 1.5 }
            && !features.contains { point.distance(to: $0.center) < footprint + $0.radius + radius * 1.5 }
        }
        let holeRadius = radius * 1.55
        for point in candidates where holes.count < min(24, max(0, recipe.holeCount)) {
            if available(point, footprint: holeRadius) { holes.append(MazeHole(center: point, radius: holeRadius)) }
        }
        let requests: [(MazeFeature.Kind, Int)] = [(.bumper, recipe.bumperCount), (.magnet, recipe.magnetCount), (.fan, recipe.fanCount)]
        for (kind, requested) in requests {
            var placed = 0
            for point in candidates where placed < min(kind == .bumper ? 18 : 8, max(0, requested)) {
                let featureRadius = radius * (kind == .bumper ? 1.6 : 1.2)
                if available(point, footprint: featureRadius) {
                    let directions = [Vec2(1, 0), Vec2(0, -1), Vec2(-1, 0), Vec2(0, 1)]
                    features.append(MazeFeature(kind: kind, center: point, radius: featureRadius,
                                                direction: directions[random.index(directions.count)]))
                    placed += 1
                }
            }
        }

        let styleName = recipe.style == .switchbacks ? "Switchbacks" : recipe.style.rawValue.capitalized
        let difficultyName = recipe.difficulty == .easy ? "Gentle" : recipe.difficulty == .medium ? "Balanced" : "Precise"
        let title = titleFromDescription(recipe.description, fallback: "Your \(styleName)")
        let level = MazeLevel(id: "generated-\(seed)-\(recipe.style.rawValue)", title: title,
                              subtitle: "\(styleName) · \(difficultyName) · \(holes.count) holes",
                              seed: seed, theme: recipe.theme, difficulty: recipe.difficulty,
                              width: width, height: height, walls: walls, holes: holes, features: features,
                              start: center(startCell), goal: center(goalCell), ballRadius: radius, solution: solution)
        try MazeValidator.validate(level)
        return level
    }

    static func perimeter(width: Double = 1, height: Double = 1.45, inset: Double = 0.035,
                          thickness: Double = 0.02) -> [MazeWall] {
        let a = Vec2(inset, inset), b = Vec2(width - inset, inset)
        let c = Vec2(width - inset, height - inset), d = Vec2(inset, height - inset)
        return [MazeWall(a: a, b: b, thickness: thickness), MazeWall(a: b, b: c, thickness: thickness),
                MazeWall(a: c, b: d, thickness: thickness), MazeWall(a: d, b: a, thickness: thickness)]
    }

    private static func titleFromDescription(_ description: String, fallback: String) -> String {
        let clean = description.components(separatedBy: .controlCharacters).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return fallback }
        if clean.count <= 52 { return clean.prefix(1).uppercased() + clean.dropFirst() }
        let prefix = String(clean.prefix(49))
        let shortened = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
        return shortened.prefix(1).uppercased() + shortened.dropFirst() + "…"
    }

    private static func mergeCollinear(_ input: [MazeWall]) -> [MazeWall] {
        // Joining contiguous segments removes seams in both collision capsules and Metal.
        var result: [MazeWall] = []
        let vertical = input.filter { abs($0.a.x - $0.b.x) < 1e-10 }.sorted {
            abs($0.a.x - $1.a.x) > 1e-10 ? $0.a.x < $1.a.x : min($0.a.y, $0.b.y) < min($1.a.y, $1.b.y)
        }
        let horizontal = input.filter { abs($0.a.y - $0.b.y) < 1e-10 }.sorted {
            abs($0.a.y - $1.a.y) > 1e-10 ? $0.a.y < $1.a.y : min($0.a.x, $0.b.x) < min($1.a.x, $1.b.x)
        }
        for group in [vertical, horizontal] {
            for wall in group {
                let isVertical = abs(wall.a.x - wall.b.x) < 1e-10
                let start = isVertical ? Vec2(wall.a.x, min(wall.a.y, wall.b.y)) : Vec2(min(wall.a.x, wall.b.x), wall.a.y)
                let end = isVertical ? Vec2(wall.a.x, max(wall.a.y, wall.b.y)) : Vec2(max(wall.a.x, wall.b.x), wall.a.y)
                if let last = result.last, last.b.distance(to: start) < 1e-9,
                   abs((last.b - last.a).normalized.dot((end - start).normalized) - 1) < 1e-9 {
                    result[result.count - 1].b = end
                } else { result.append(MazeWall(a: start, b: end, thickness: wall.thickness)) }
            }
        }
        return result
    }
}

private struct Edge: Hashable {
    let a: Int
    let b: Int
    init(_ a: Int, _ b: Int) { self.a = min(a, b); self.b = max(a, b) }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func index(_ count: Int) -> Int { Int(next() % UInt64(max(1, count))) }
    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for index in stride(from: array.count - 1, through: 1, by: -1) { array.swapAt(index, self.index(index + 1)) }
    }
}

private struct DisjointSet {
    var parents: [Int]
    init(count: Int) { parents = Array(0..<count) }
    mutating func root(_ index: Int) -> Int {
        var cursor = index
        while parents[cursor] != cursor { parents[cursor] = parents[parents[cursor]]; cursor = parents[cursor] }
        return cursor
    }
    mutating func join(_ a: Int, _ b: Int) -> Bool {
        let x = root(a), y = root(b)
        guard x != y else { return false }
        parents[y] = x; return true
    }
}
