import Foundation
import SwiftData
import LiltCore

@Model
final class StoredMaze {
    @Attribute(.unique) var mazeID: String
    var title: String
    var prompt: String
    var createdAt: Date
    var levelData: Data
    var recipeData: Data?
    var generatorVersion: Int = 1
    var interpretationMethod: String = "Local prompt interpreter"

    init(level: MazeLevel, prompt: String, recipe: MazeRecipe? = nil, method: String = "Local prompt interpreter") throws {
        mazeID = level.id
        title = level.title
        self.prompt = prompt
        createdAt = .now
        levelData = try JSONEncoder().encode(level)
        recipeData = try recipe.map { try JSONEncoder().encode($0) }
        interpretationMethod = method
    }

    var level: MazeLevel? { try? JSONDecoder().decode(MazeLevel.self, from: levelData) }
}

struct ReplayPoint: Codable, Sendable {
    var time: Double
    var position: Vec2
}

@Model
final class RunRecord {
    @Attribute(.unique) var mazeID: String
    var time: Double
    var replayData: Data
    var completedAt: Date

    init(mazeID: String, time: Double, replay: [ReplayPoint]) throws {
        self.mazeID = mazeID
        self.time = time
        replayData = try JSONEncoder().encode(replay)
        completedAt = .now
    }

    var replay: [ReplayPoint] { (try? JSONDecoder().decode([ReplayPoint].self, from: replayData)) ?? [] }
}
