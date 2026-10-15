import SwiftUI
import SwiftData
import LiltCore

private enum MenuDestination: Hashable { case levels, create, collection }

struct LiltRootView: View {
    @State private var path: [MenuDestination] = []
    @State private var selectedLevel: MazeLevel?
    @State private var settingsPresented = false
    @Query private var records: [RunRecord]

    var body: some View {
        NavigationStack(path: $path) {
            PlayHomeView(records: records, play: { selectedLevel = $0 },
                levels: { path.append(.levels) }, create: { path.append(.create) },
                collection: { path.append(.collection) }, settings: { settingsPresented = true })
                .navigationDestination(for: MenuDestination.self) { destination in
                    switch destination {
                    case .levels: LevelSelectView(records: records, play: { selectedLevel = $0 })
                    case .create: CreateMazeView(play: { selectedLevel = $0 })
                    case .collection: CollectionView(play: { selectedLevel = $0 }, create: { path.append(.create) })
                    }
                }
        }
        .tint(LiltTheme.ink)
        .fullScreenCover(item: $selectedLevel) { level in
            GameView(level: level, previousRecord: records.first(where: { $0.mazeID == level.id })) { selectedLevel = $0 }
                .id(level.id)
        }
        .sheet(isPresented: $settingsPresented) { SettingsView() }
        .preferredColorScheme(.light)
    }
}
