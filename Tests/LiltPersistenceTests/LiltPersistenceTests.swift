import Foundation
import SwiftData
import Testing
import LiltCore
@testable import LiltPersistence

@Test @MainActor
func nativeStoreReopensWithExactBoardRecipeAndGhost() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-store-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("Mazes.store")
    let recipe = RecipeParser.parse("A medium jade garden with four holes, two bumpers, one magnet and one fan")
    let level = try MazeGenerator.generate(recipe: recipe, seed: 0x1020_3040_5060_7080)
    let replay = [
        ReplayPoint(time: 0, position: level.start),
        ReplayPoint(time: 6.5, position: level.solution[level.solution.count / 2]),
        ReplayPoint(time: 13, position: level.goal)
    ]

    // The writer owns all container/context/model references. Returning releases
    // them before a new container opens the same native disk store.
    try autoreleasepool {
        let container = try diskContainer(at: storeURL)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let stored = try StoredMaze(level: level, prompt: recipe.description, recipe: recipe, method: "Persistence regression fixture")
        stored.generatorVersion = 7
        context.insert(stored)
        try context.save()
        #expect(try RunPersistence.saveBest(mazeID: level.id, time: 13, replay: replay, context: context))
    }

    #expect(FileManager.default.fileExists(atPath: storeURL.path))
    let databaseHeader = try Data(contentsOf: storeURL).prefix(16)
    #expect(String(decoding: databaseHeader, as: UTF8.self) == "SQLite format 3\0")

    try autoreleasepool {
        let container = try diskContainer(at: storeURL)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let storedMazes = try context.fetch(FetchDescriptor<StoredMaze>())
        let stored = try #require(storedMazes.first)
        #expect(storedMazes.count == 1)
        #expect(stored.level == level)
        #expect(stored.level?.seed == level.seed)
        #expect(stored.prompt == recipe.description)
        #expect(stored.generatorVersion == 7)
        #expect(stored.interpretationMethod == "Persistence regression fixture")
        let recipeData = try #require(stored.recipeData)
        #expect(try JSONDecoder().decode(MazeRecipe.self, from: recipeData) == recipe)
        let records = try context.fetch(FetchDescriptor<RunRecord>())
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.mazeID == level.id)
        #expect(record.time == 13)
        expectReplay(record.replay, matches: replay)
    }
}

@Test @MainActor
func subsequentWinsKeepTheFastestTimeAndItsGhostWithoutDuplicateRows() throws {
    let schema = Schema([StoredMaze.self, RunRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let first = [ReplayPoint(time: 0, position: Vec2(0.1, 0.2)), ReplayPoint(time: 12, position: Vec2(0.8, 1.2))]
    let slower = [ReplayPoint(time: 0, position: Vec2(0.3, 0.4)), ReplayPoint(time: 18, position: Vec2(0.8, 1.2))]
    let faster = [ReplayPoint(time: 0, position: Vec2(0.1, 0.2)), ReplayPoint(time: 8, position: Vec2(0.8, 1.2))]

    #expect(try RunPersistence.saveBest(mazeID: "first-time-maze", time: 12, replay: first, context: context))
    #expect(try !RunPersistence.saveBest(mazeID: "first-time-maze", time: 18, replay: slower, context: context))
    #expect(try !RunPersistence.saveBest(mazeID: "first-time-maze", time: 12, replay: slower, context: context))
    let initialRecords = try context.fetch(FetchDescriptor<RunRecord>())
    let initial = try #require(initialRecords.first)
    #expect(initialRecords.count == 1)
    #expect(initial.time == 12)
    expectReplay(initial.replay, matches: first)
    let initialIdentifier = initial.persistentModelID

    #expect(try RunPersistence.saveBest(mazeID: "first-time-maze", time: 8, replay: faster, context: context))
    let finalRecords = try context.fetch(FetchDescriptor<RunRecord>())
    let final = try #require(finalRecords.first)
    #expect(finalRecords.count == 1)
    #expect(final.persistentModelID == initialIdentifier)
    #expect(final.time == 8)
    expectReplay(final.replay, matches: faster)

    // A newly opened context sees the saved best, rather than a captured record
    // from the beginning of the play session.
    let laterContext = ModelContext(container)
    laterContext.autosaveEnabled = false
    #expect(try !RunPersistence.saveBest(mazeID: "first-time-maze", time: 10, replay: first, context: laterContext))
    let reread = try laterContext.fetch(FetchDescriptor<RunRecord>())
    #expect(reread.count == 1)
    #expect(reread.first?.time == 8)
    if let rereadRecord = reread.first { expectReplay(rereadRecord.replay, matches: faster) }
}

@MainActor
private func diskContainer(at url: URL) throws -> ModelContainer {
    let schema = Schema([StoredMaze.self, RunRecord.self])
    let configuration = ModelConfiguration("PersistenceFixture", schema: schema, url: url, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func expectReplay(_ actual: [ReplayPoint], matches expected: [ReplayPoint]) {
    #expect(actual.count == expected.count)
    for (actualPoint, expectedPoint) in zip(actual, expected) {
        #expect(actualPoint.time == expectedPoint.time)
        #expect(actualPoint.position == expectedPoint.position)
    }
}
