import Foundation
import Testing
@testable import LiltCore

private let validInterpretation = #"{"title":"Quiet Garden","style":"garden","difficulty":"easy","theme":"jade","holes":2,"bumpers":0,"magnets":0,"fans":0}"#

@Test func modelRecipePreservesExplicitPlayerCountsAndPreferences() throws {
    let value = try JSONDecoder().decode(MazeInterpretation.self, from: Data(validInterpretation.utf8))
    let recipe = try value.recipe(description: "A hard midnight spiral with no holes and four bumpers")
    #expect(recipe.holeCount == 0)
    #expect(recipe.bumperCount == 4)
    #expect(recipe.difficulty == .hard)
    #expect(recipe.theme == .midnight)
    #expect(recipe.style == .spiral)
    let level = try MazeGenerator.generate(recipe: recipe, seed: 42)
    #expect(level.holes.isEmpty)
    try MazeValidator.validate(level)
}

@Test func modelRecipesRejectUnsupportedGeometryRequestsAndCounts() throws {
    for invalid in [
        validInterpretation.replacingOccurrences(of: "\"garden\"", with: "\"teleport\""),
        validInterpretation.replacingOccurrences(of: "\"jade\"", with: "\"lava\""),
        validInterpretation.replacingOccurrences(of: "\"holes\":2", with: "\"holes\":-1"),
        validInterpretation.replacingOccurrences(of: "\"fans\":0", with: "\"fans\":4"),
        validInterpretation.replacingOccurrences(of: "Quiet Garden", with: "One Two Three Four Five Six"),
        validInterpretation.replacingOccurrences(of: "Quiet Garden", with: ""),
        validInterpretation.replacingOccurrences(of: "\"holes\":2", with: "\"holes\":true"),
    ] {
        #expect(throws: (any Error).self) {
            let value = try JSONDecoder().decode(MazeInterpretation.self, from: Data(invalid.utf8))
            try value.validate()
        }
    }
}
