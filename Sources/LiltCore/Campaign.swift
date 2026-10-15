import Foundation

/// Original layouts and seeds, progressing from learning to tilt through mixed mechanisms.
/// These boards were authored for Lilt; no historic game's level geometry is reproduced.
public enum Campaign {
    public static let levels: [MazeLevel] = {
        let frame = MazeGenerator.perimeter()
        let first = MazeLevel(id: "campaign-01", title: "A Little Lilt", subtitle: "01 · Learn the weight of the ball",
                              walls: frame, start: Vec2(0.22, 1.18), goal: Vec2(0.76, 0.26), ballRadius: 0.027,
                              solution: [Vec2(0.22, 1.18), Vec2(0.76, 0.26)])
        let second = MazeLevel(id: "campaign-02", title: "Around the Corner", subtitle: "02 · Brake before the turn",
                               walls: frame + [MazeWall(a: Vec2(0.035, 0.76), b: Vec2(0.69, 0.76), thickness: 0.024)],
                               start: Vec2(0.22, 1.20), goal: Vec2(0.50, 0.26), ballRadius: 0.027,
                               solution: [Vec2(0.22, 1.20), Vec2(0.82, 1.20), Vec2(0.82, 0.40), Vec2(0.50, 0.40), Vec2(0.50, 0.26)])
        let thirdRoute = [Vec2(0.18, 1.21), Vec2(0.82, 1.21), Vec2(0.82, 0.71),
                          Vec2(0.18, 0.71), Vec2(0.18, 0.22), Vec2(0.78, 0.22)]
        let third = MazeLevel(id: "campaign-03", title: "The First Drop", subtitle: "03 · Small tilts, steady hands",
                              walls: frame + [MazeWall(a: Vec2(0.035, 0.94), b: Vec2(0.66, 0.94), thickness: 0.024),
                                              MazeWall(a: Vec2(0.34, 0.48), b: Vec2(0.965, 0.48), thickness: 0.024)],
                              holes: [MazeHole(center: Vec2(0.48, 1.09), radius: 0.041),
                                      MazeHole(center: Vec2(0.58, 0.59), radius: 0.041),
                                      MazeHole(center: Vec2(0.41, 0.34), radius: 0.041)],
                              start: thirdRoute.first!, goal: thirdRoute.last!, ballRadius: 0.026, solution: thirdRoute)
        let fourthRoute = [Vec2(0.18, 1.29), Vec2(0.82, 1.29), Vec2(0.82, 0.98),
                           Vec2(0.18, 0.98), Vec2(0.18, 0.70), Vec2(0.82, 0.70),
                           Vec2(0.82, 0.42), Vec2(0.18, 0.42), Vec2(0.18, 0.18), Vec2(0.78, 0.18)]
        let fourth = MazeLevel(id: "campaign-04", title: "Measured Steps", subtitle: "04 · Find a rhythm through the bends",
                               walls: frame + [MazeWall(a: Vec2(0.035, 1.12), b: Vec2(0.69, 1.12), thickness: 0.02),
                                               MazeWall(a: Vec2(0.31, 0.85), b: Vec2(0.965, 0.85), thickness: 0.02),
                                               MazeWall(a: Vec2(0.035, 0.56), b: Vec2(0.69, 0.56), thickness: 0.02),
                                               MazeWall(a: Vec2(0.31, 0.30), b: Vec2(0.965, 0.30), thickness: 0.02)],
                               holes: [MazeHole(center: Vec2(0.50, 1.20), radius: 0.037),
                                       MazeHole(center: Vec2(0.50, 0.77), radius: 0.037),
                                       MazeHole(center: Vec2(0.50, 0.36), radius: 0.037)],
                               start: fourthRoute.first!, goal: fourthRoute.last!, ballRadius: 0.024, solution: fourthRoute)
        var output = [first, second, third, fourth]
        let specifications: [(String, String, MazeRecipe, UInt64)] = [
            ("Cross Grain", "Follow the longer route", MazeRecipe(difficulty: .easy, style: .switchbacks, holeCount: 4), 0xA105),
            ("Spring Garden", "Meet the spring bumpers", MazeRecipe(difficulty: .easy, theme: .jade, style: .pinball, holeCount: 3, bumperCount: 3), 0xA106),
            ("Quiet Attraction", "Feel the pull of a magnet", MazeRecipe(difficulty: .medium, theme: .jade, style: .garden, holeCount: 4, magnetCount: 2), 0xA107),
            ("A Change in the Air", "Lean against the breeze", MazeRecipe(difficulty: .medium, theme: .jade, style: .garden, holeCount: 5, fanCount: 2), 0xA108),
            ("Inward", "Read a coil one turn at a time", MazeRecipe(difficulty: .medium, style: .spiral, holeCount: 5), 0xA109),
            ("Night Passage", "Narrower corridors, finer control", MazeRecipe(difficulty: .hard, theme: .midnight, style: .switchbacks, holeCount: 9), 0xA110),
            ("After Hours", "Control the rebound", MazeRecipe(difficulty: .hard, theme: .midnight, style: .pinball, holeCount: 9, bumperCount: 5, fanCount: 1), 0xA111),
            ("Everything in Motion", "Weight, wind, springs, and fields", MazeRecipe(difficulty: .hard, theme: .midnight, style: .spiral, holeCount: 10, bumperCount: 2, magnetCount: 2, fanCount: 2), 0xA112)
        ]
        for (offset, specification) in specifications.enumerated() {
            do {
                var level = try MazeGenerator.generate(recipe: specification.2, seed: specification.3)
                level.id = String(format: "campaign-%02d", offset + 5)
                level.title = specification.0
                level.subtitle = String(format: "%02d · %@", offset + 5, specification.1)
                output.append(level)
            } catch { preconditionFailure("Invalid campaign level: \(error)") }
        }
        return output
    }()
}
