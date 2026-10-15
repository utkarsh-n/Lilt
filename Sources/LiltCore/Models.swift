import Foundation

public struct Vec2: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)
    public var lengthSquared: Double { x * x + y * y }
    public var length: Double { sqrt(lengthSquared) }
    public var normalized: Vec2 { length > 1e-12 ? self / length : .zero }
    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    public func distance(to other: Vec2) -> Double { (self - other).length }
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func * (a: Vec2, b: Double) -> Vec2 { Vec2(a.x * b, a.y * b) }
    public static func * (a: Double, b: Vec2) -> Vec2 { b * a }
    public static func / (a: Vec2, b: Double) -> Vec2 { Vec2(a.x / b, a.y / b) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }
    public static func *= (a: inout Vec2, b: Double) { a = a * b }
}

public struct MazeWall: Codable, Sendable, Hashable {
    public var a: Vec2
    public var b: Vec2
    public var thickness: Double
    public init(a: Vec2, b: Vec2, thickness: Double = 0.018) {
        self.a = a; self.b = b; self.thickness = thickness
    }
}

public struct MazeHole: Codable, Sendable, Hashable {
    public var center: Vec2
    public var radius: Double
    public init(center: Vec2, radius: Double = 0.035) { self.center = center; self.radius = radius }
}

public struct MazeFeature: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case bumper, magnet, fan }
    public var kind: Kind
    public var center: Vec2
    public var radius: Double
    public var direction: Vec2
    public init(kind: Kind, center: Vec2, radius: Double = 0.035, direction: Vec2 = Vec2(0, -1)) {
        self.kind = kind; self.center = center; self.radius = radius; self.direction = direction
    }
}

public enum MazeTheme: String, Codable, Sendable, CaseIterable { case oak, jade, midnight }
public enum MazeDifficulty: String, Codable, Sendable, CaseIterable { case easy, medium, hard }
public enum MazeStyle: String, Codable, Sendable, CaseIterable { case switchbacks, spiral, garden, pinball }

public struct MazeLevel: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var seed: UInt64
    public var theme: MazeTheme
    public var difficulty: MazeDifficulty
    public var width: Double
    public var height: Double
    public var walls: [MazeWall]
    public var holes: [MazeHole]
    public var features: [MazeFeature]
    public var start: Vec2
    public var goal: Vec2
    public var ballRadius: Double
    /// A connected route with clearance for the entire ball, retained for hints and validation.
    public var solution: [Vec2]

    public init(id: String, title: String, subtitle: String = "", seed: UInt64 = 0,
                theme: MazeTheme = .oak, difficulty: MazeDifficulty = .easy,
                width: Double = 1, height: Double = 1.45,
                walls: [MazeWall] = [], holes: [MazeHole] = [], features: [MazeFeature] = [],
                start: Vec2, goal: Vec2, ballRadius: Double = 0.024, solution: [Vec2] = []) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.seed = seed
        self.theme = theme; self.difficulty = difficulty; self.width = width; self.height = height
        self.walls = walls; self.holes = holes; self.features = features
        self.start = start; self.goal = goal; self.ballRadius = ballRadius; self.solution = solution
    }
}

public struct MazeRecipe: Codable, Sendable, Hashable {
    public var description: String
    public var difficulty: MazeDifficulty
    public var theme: MazeTheme
    public var style: MazeStyle
    public var holeCount: Int
    public var bumperCount: Int
    public var magnetCount: Int
    public var fanCount: Int
    public init(description: String = "A gentle wooden labyrinth", difficulty: MazeDifficulty = .easy,
                theme: MazeTheme = .oak, style: MazeStyle = .switchbacks,
                holeCount: Int = 3, bumperCount: Int = 0, magnetCount: Int = 0, fanCount: Int = 0) {
        self.description = description; self.difficulty = difficulty; self.theme = theme; self.style = style
        self.holeCount = holeCount; self.bumperCount = bumperCount
        self.magnetCount = magnetCount; self.fanCount = fanCount
    }
}

public enum PhysicsStatus: String, Codable, Sendable { case ready, playing, falling, won }
public enum PhysicsEvent: Sendable, Equatable { case impact(Double), fell, won }
