import Foundation
import SwiftData

/// Reads the stored best at completion time, including when this play session
/// began before the player's first record existed.
@MainActor
enum RunPersistence {
    @discardableResult
    static func saveBest(
        mazeID: String,
        time: Double,
        replay: [ReplayPoint],
        context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<RunRecord>(predicate: #Predicate { $0.mazeID == mazeID })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            guard time < record.time else { return false }
            let encodedReplay = try JSONEncoder().encode(replay)
            record.time = time
            record.replayData = encodedReplay
            record.completedAt = .now
        } else {
            context.insert(try RunRecord(mazeID: mazeID, time: time, replay: replay))
        }
        try context.save()
        return true
    }
}
