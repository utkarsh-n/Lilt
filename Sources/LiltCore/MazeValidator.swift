import Foundation

/// Validation is geometric, with the ball's radius included. A route between cell centers
/// alone is insufficient: every continuous route segment must clear the inflated walls.
public enum MazeValidator {
    public static func validate(_ level: MazeLevel) throws {
        guard level.width.isFinite, level.height.isFinite, level.ballRadius.isFinite,
              level.width > 0, level.height > 0, level.ballRadius > 0,
              level.ballRadius * 8 < min(level.width, level.height) else {
            throw MazeGenerationError.invalidDimensions
        }
        func finite(_ point: Vec2) -> Bool { point.x.isFinite && point.y.isFinite }
        func inside(_ point: Vec2) -> Bool {
            finite(point) && point.x >= level.ballRadius && point.x <= level.width - level.ballRadius
            && point.y >= level.ballRadius && point.y <= level.height - level.ballRadius
        }
        guard inside(level.start), inside(level.goal),
              level.walls.allSatisfy({ finite($0.a) && finite($0.b) && $0.thickness.isFinite && $0.thickness > 0 }),
              level.holes.allSatisfy({ finite($0.center) && $0.radius.isFinite && $0.radius > 0 }),
              level.features.allSatisfy({ finite($0.center) && finite($0.direction) && $0.radius.isFinite && $0.radius > 0 }) else {
            throw MazeGenerationError.invalidGeometry
        }
        guard level.solution.count >= 2,
              level.solution.first!.distance(to: level.start) < 1e-8,
              level.solution.last!.distance(to: level.goal) < 1e-8,
              level.solution.allSatisfy(inside) else { throw MazeGenerationError.unreachableGoal }
        for (a, b) in zip(level.solution, level.solution.dropFirst()) {
            for wall in level.walls {
                let clearance = Geometry.segmentDistance(a, b, wall.a, wall.b)
                if clearance + 1e-8 < level.ballRadius + wall.thickness * 0.5 {
                    throw MazeGenerationError.blockedSolution
                }
            }
            for hole in level.holes {
                if Geometry.pointSegmentDistance(hole.center, a, b) < hole.radius + level.ballRadius * 0.8 {
                    throw MazeGenerationError.blockedSolution
                }
            }
            for bumper in level.features where bumper.kind == .bumper {
                if Geometry.pointSegmentDistance(bumper.center, a, b) < bumper.radius + level.ballRadius {
                    throw MazeGenerationError.blockedSolution
                }
            }
        }
    }
}

extension Geometry {
    static func segmentDistance(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Double {
        let ab = b - a, cd = d - c
        func cross(_ x: Vec2, _ y: Vec2) -> Double { x.x * y.y - x.y * y.x }
        let denominator = cross(ab, cd)
        if abs(denominator) > 1e-14 {
            let t = cross(c - a, cd) / denominator
            let u = cross(c - a, ab) / denominator
            if t >= 0, t <= 1, u >= 0, u <= 1 { return 0 }
        }
        return min(pointSegmentDistance(a, c, d), pointSegmentDistance(b, c, d),
                   pointSegmentDistance(c, a, b), pointSegmentDistance(d, a, b))
    }
}
