import SwiftUI
import SwiftData
import OfflineIntelligenceMLX

@main
struct LiltApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer?
    private let storageError: String?

    init() {
        do {
            container = try ModelContainer(for: StoredMaze.self, RunRecord.self)
            storageError = nil
        } catch {
            container = nil
            storageError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                LiltRootView()
                    .modelContainer(container)
                    .tint(LiltTheme.green)
                    .onChange(of: scenePhase) { _, phase in
                        if phase != .active { Task { await OfflineTextService.shared.unload() } }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                        Task { await OfflineTextService.shared.unload() }
                    }
            } else {
                ContentUnavailableView("Collection unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(storageError ?? "Storage could not be opened. Please relaunch Lilt."))
            }
        }
    }
}
