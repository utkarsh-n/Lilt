import Foundation
import OfflineIntelligence
import OfflineIntelligenceMLX
import Observation
import LiltCore

struct CreatedMaze {
    var level: MazeLevel
    var recipe: MazeRecipe
    var method: String
    var note: String?
}

@MainActor
@Observable
final class MazeCreation {
    private(set) var isGenerating = false
    private(set) var progress = ""
    private(set) var result: CreatedMaze?
    private(set) var error: String?

    var availabilityMessage: String {
        let choice = OfflineModelChoice.persisted()
        return (try? LocalModelFiles.directory(for: choice)) != nil
            ? "\(choice.title) · offline on this iPhone" : "Local prompt interpreter · model files unavailable"
    }

    func generate(prompt: String, difficulty: MazeDifficulty?, theme: MazeTheme?) async {
        guard !isGenerating else { return }
        let text = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_200))
        guard !text.isEmpty else { error = "Describe the labyrinth you want to play."; return }
        isGenerating = true
        error = nil
        result = nil
        defer { isGenerating = false }
        var recipe = RecipeParser.parse(text)
        var title: String?
        var method = "Local prompt interpreter"
        var note: String?
        let choice = OfflineModelChoice.persisted()
        do {
            progress = "Finding the shape of your idea…"
            let directory = try LocalModelFiles.directory(for: choice)
            let answer = try await OfflineTextService.shared.respond(to: GenerationRequest(system: """
                Interpret a description of a single marble tilt labyrinth. Return only one JSON object with exactly
                these fields: title (short string, at most five words), style (switchbacks, spiral, garden, pinball),
                difficulty (easy, medium, hard), theme (oak, jade, midnight), holes (integer 0...12),
                bumpers (integer 0...6), magnets (integer 0...3), fans (integer 0...3).
                Oak means warm wood, jade means green garden or ceramic, midnight means dark space or metal.
                Respect negations and explicit counts. Set bumpers, magnets and fans to zero unless requested.
                Gentle mazes should have few holes. Do not invent unsupported gameplay or wall coordinates.
                No markdown fences, explanation or extra fields.
                """, prompt: text, maxOutputTokens: 384, timeoutSeconds: 90),
                model: choice.descriptor, directory: directory)
            try Task.checkCancellation()
            let value = try StructuredOutput.decode(answer.text, as: MazeInterpretation.self) { try $0.validate() }
            recipe = try value.recipe(description: text)
            title = String(value.title.prefix(70))
            method = "\(choice.title) · offline on-device"
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            note = "\(choice.title) could not return a valid recipe. The local interpreter built this version instead. \(error.localizedDescription)"
        }
        recipe = RecipeParser.enforcingExplicitCounts(in: text, on: recipe)
        recipe = RecipeParser.enforcingExplicitPreferences(in: text, on: recipe)
        if let difficulty { recipe.difficulty = difficulty }
        if let theme { recipe.theme = theme }
        progress = "Carving walls and checking the route…"
        let seed = UInt64.random(in: 1...UInt64.max)
        do {
            let immutableRecipe = recipe
            var level = try await Task.detached(priority: .userInitiated) {
                try MazeGenerator.generate(recipe: immutableRecipe, seed: seed)
            }.value
            try Task.checkCancellation()
            if let title, !title.isEmpty { level.title = title }
            result = CreatedMaze(level: level, recipe: recipe, method: method, note: note)
        } catch is CancellationError {
            return
        } catch {
            self.error = "That board couldn't be built safely. Try a simpler description. \(error.localizedDescription)"
        }
    }
}
