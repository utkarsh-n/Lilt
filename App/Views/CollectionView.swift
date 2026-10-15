import SwiftUI
import SwiftData
import LiltCore

struct CollectionView: View {
    let play: (MazeLevel) -> Void
    let create: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredMaze.createdAt, order: .reverse) private var mazes: [StoredMaze]
    @State private var storageError: String?

    var body: some View {
        Group {
            if mazes.isEmpty {
                VStack {
                    Spacer()
                    ContentUnavailableView {
                        Label("No saved mazes", systemImage: "square.stack")
                    } description: {
                        Text("Generate a maze and save it here to play again.")
                    } actions: {
                        Button("Generate a maze", action: create).buttonStyle(MetalButtonStyle())
                    }
                    .foregroundStyle(LiltTheme.ink)
                    .padding(14)
                    .classicPanel()
                    .padding(18)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text("\(mazes.count) saved \(mazes.count == 1 ? "maze" : "mazes")")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(LiltTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16).classicPanel()
                        ForEach(mazes) { maze in
                            HStack(alignment: .center, spacing: 16) {
                                if let level = maze.level {
                                    MazePreview(level: level).frame(width: 88, height: 128)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(maze.title).font(.headline).foregroundStyle(LiltTheme.ink).lineLimit(2)
                                        Text(maze.prompt).font(.caption).foregroundStyle(LiltTheme.muted).lineLimit(3)
                                        Text(maze.createdAt, style: .date).font(.caption2).foregroundStyle(LiltTheme.muted)
                                        Button("Play", systemImage: "play.fill") { play(level) }
                                            .buttonStyle(MetalButtonStyle(compact: true)).accessibilityIdentifier("playSaved")
                                    }
                                } else {
                                    Label("This maze couldn't be read", systemImage: "exclamationmark.triangle")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .classicPanel()
                            .contextMenu { Button("Delete maze", systemImage: "trash", role: .destructive) { remove(maze) } }
                            .accessibilityAction(named: "Delete maze") { remove(maze) }
                        }
                        if let storageError { Text(storageError).font(.caption).foregroundStyle(.red).padding(12).classicPanel() }
                    }.padding(18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WoodSurface() }
        .navigationTitle("My mazes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func remove(_ maze: StoredMaze) {
        modelContext.delete(maze)
        do { try modelContext.save() }
        catch { modelContext.rollback(); storageError = "Couldn't delete this maze. \(error.localizedDescription)" }
    }
}
