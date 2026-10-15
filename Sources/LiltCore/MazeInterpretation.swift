import Foundation

/// A language model proposes a bounded recipe; the generator retains authority over geometry and routes.
public struct MazeInterpretation: Codable, Sendable {
    public let title: String
    public let style: MazeStyle
    public let difficulty: MazeDifficulty
    public let theme: MazeTheme
    public let holes: Int
    public let bumpers: Int
    public let magnets: Int
    public let fans: Int

    public func validate() throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, title.count <= 70, cleanTitle.split(whereSeparator: \.isWhitespace).count <= 5,
              (0...12).contains(holes), (0...6).contains(bumpers),
              (0...3).contains(magnets), (0...3).contains(fans) else { throw InvalidMazeInterpretation() }
    }

    public func recipe(description: String) throws -> MazeRecipe {
        try validate()
        let proposed = MazeRecipe(description: description, difficulty: difficulty, theme: theme, style: style,
                                  holeCount: holes, bumperCount: bumpers, magnetCount: magnets, fanCount: fans)
        let counted = RecipeParser.enforcingExplicitCounts(in: description, on: proposed)
        return RecipeParser.enforcingExplicitPreferences(in: description, on: counted)
    }
}

public struct InvalidMazeInterpretation: Error, LocalizedError, Sendable {
    public var errorDescription: String? { "The model returned an unsupported maze recipe." }
}
