import SwiftUI
import SwiftData
import LiltCore

struct CreateMazeView: View {
    let play: (MazeLevel) -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var creation = MazeCreation()
    @State private var prompt = "A gentle wooden maze with wide turns and a few holes."
    @State private var difficulty: MazeDifficulty?
    @State private var theme: MazeTheme?
    @State private var generationTask: Task<Void, Never>?
    @State private var savedID: String?
    @State private var storageError: String?
    @FocusState private var promptFocused: Bool
    private let examples = [
        ("Quiet garden", "A peaceful jade garden with wide paths, two holes and no bumpers."),
        ("Spiral", "A tricky wooden spiral with five holes, winding toward the center."),
        ("Moon maze", "An expert midnight maze with magnets, fans and narrow passages."),
        ("Pinball", "A playful maple pinball labyrinth with four bumpers and no holes.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Generative mode")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LiltTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Describe a maze, then tilt to play.")
                        .font(.subheadline).foregroundStyle(LiltTheme.muted)
                }
                .padding(18)
                .classicPanel()
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: "pencil").foregroundStyle(LiltTheme.green)
                        Text("Maze description").font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    TextEditor(text: $prompt)
                        .frame(minHeight: 108)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .focused($promptFocused)
                        .accessibilityLabel("Labyrinth description")
                        .accessibilityIdentifier("mazePrompt")
                        .onChange(of: prompt) { _, value in if value.count > 1_200 { prompt = String(value.prefix(1_200)) } }
                    HStack {
                        Text("Try a spiral, a garden, or a pinball maze.")
                        Spacer(minLength: 2)
                        Text("\(prompt.count)/1200").monospacedDigit()
                    }.font(.caption2).foregroundStyle(LiltTheme.muted)
                }
                .padding(17)
                .classicPanel()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(examples, id: \.0) { title, text in
                            Button(title) { prompt = text; difficulty = nil; theme = nil; promptFocused = false }
                                .buttonStyle(MetalButtonStyle(compact: true))
                                .accessibilityIdentifier("example_\(title)")
                        }
                    }.padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 15) {
                    Text("Board options").font(.headline).foregroundStyle(LiltTheme.ink)
                    Picker("Difficulty", selection: $difficulty) {
                        Text("From words").tag(MazeDifficulty?.none)
                        ForEach(MazeDifficulty.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }.pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        Text("Material").font(.subheadline).foregroundStyle(LiltTheme.muted)
                        Spacer(minLength: 0)
                        Button { theme = nil } label: {
                            Image(systemName: "sparkles")
                                .frame(width: 44, height: 44)
                                .background(theme == nil ? LiltTheme.green.opacity(0.13) : Color.clear, in: Circle())
                                .overlay { Circle().stroke(theme == nil ? LiltTheme.green : LiltTheme.line, lineWidth: 1) }
                        }
                        .accessibilityLabel("Material from description").accessibilityAddTraits(theme == nil ? [.isSelected] : [])
                        ForEach(MazeTheme.allCases, id: \.self) { value in
                            Button { theme = value } label: {
                                Circle().fill(value.swatch).frame(width: 31, height: 31)
                                    .frame(width: 44, height: 44)
                                    .overlay { Circle().stroke(theme == value ? LiltTheme.ink : Color.clear, lineWidth: 2) }
                            }
                            .accessibilityLabel(value.title).accessibilityAddTraits(theme == value ? [.isSelected] : [])
                        }
                    }.buttonStyle(.plain)
                }
                .padding(17)
                .classicPanel()

                if creation.isGenerating {
                    VStack(spacing: 13) {
                        HStack { ProgressView(); Text(creation.progress).font(.subheadline); Spacer() }
                        Button("Cancel") { generationTask?.cancel() }.buttonStyle(MetalButtonStyle(compact: true))
                    }.padding(17).classicPanel()
                } else {
                    LiltPrimaryButton(title: creation.result == nil ? "Generate maze" : "Generate another version", symbol: "sparkles") {
                        promptFocused = false
                        savedID = nil
                        storageError = nil
                        generationTask = Task { await creation.generate(prompt: prompt, difficulty: difficulty, theme: theme) }
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("generateMaze")
                }

                if let result = creation.result {
                    GeneratedBoardCard(result: result, isSaved: savedID == result.level.id,
                        play: { play(result.level) }, save: { save(result) })
                } else {
                    Label(creation.availabilityMessage, systemImage: "iphone")
                        .font(.caption).foregroundStyle(LiltTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center).padding(12).classicPanel()
                }
                if let error = creation.error ?? storageError {
                    Text(error).font(.subheadline).foregroundStyle(.red).padding(12).classicPanel().accessibilityIdentifier("creationError")
                }

                DisclosureGroup("What can I describe?") {
                    Text("Ask for winding paths, spirals, gardens, or pinball boards. Choose maple, jade, or midnight; add holes, bumpers, magnets, and fans. Qwen interprets the description offline, then explicit counts and preferences are enforced. A local interpreter provides a fallback. Every version has a checked route to the exit.")
                        .font(.caption).foregroundStyle(LiltTheme.muted).padding(.top, 8)
                }.font(.subheadline).foregroundStyle(LiltTheme.ink).padding(17).classicPanel()
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
        }
        .background { WoodSurface() }
        .navigationTitle("Generative mode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { promptFocused = false }.buttonStyle(MetalButtonStyle(compact: true)) }
        }
        .onDisappear { generationTask?.cancel() }
    }

    private func save(_ result: CreatedMaze) {
        guard savedID != result.level.id else { return }
        do {
            let saved = try StoredMaze(level: result.level, prompt: result.recipe.description, recipe: result.recipe, method: result.method)
            modelContext.insert(saved)
            try modelContext.save()
            savedID = result.level.id
        } catch {
            modelContext.rollback()
            storageError = "Couldn't save this maze. \(error.localizedDescription)"
        }
    }
}

private struct GeneratedBoardCard: View {
    let result: CreatedMaze
    let isSaved: Bool
    let play: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "Generated maze")
                    Text(result.level.title).font(.title2.weight(.semibold)).foregroundStyle(LiltTheme.ink)
                    Text("\(result.level.difficulty.title) · \(result.level.theme.title) · \(result.level.holes.count) holes")
                        .font(.caption).foregroundStyle(LiltTheme.muted)
                }
                Spacer()
                Image(systemName: "checkmark.seal").foregroundStyle(LiltTheme.green).font(.title2)
                    .accessibilityLabel("Route checked")
            }
            MazePreview(level: result.level).frame(height: 310).frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.12), radius: 15, y: 8)
            if !result.level.features.isEmpty {
                Text(featureDescription).font(.caption).foregroundStyle(LiltTheme.muted)
            }
            HStack(spacing: 12) {
                Button(action: play) { Label("Play this maze", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 36) }
                    .buttonStyle(MetalButtonStyle()).accessibilityIdentifier("playGenerated")
                Button(action: save) { Image(systemName: isSaved ? "bookmark.fill" : "bookmark").frame(width: 36, height: 36) }
                    .buttonStyle(MetalButtonStyle()).disabled(isSaved).accessibilityLabel(isSaved ? "Maze saved" : "Save maze").accessibilityIdentifier("saveGenerated")
            }
            Text(result.method + " · route checked").font(.caption2).foregroundStyle(LiltTheme.muted)
            if let note = result.note { Text(note).font(.caption).foregroundStyle(LiltTheme.muted) }
        }
        .padding(18).classicPanel()
    }

    private var featureDescription: String {
        MazeFeature.Kind.allCases.compactMap { kind -> String? in
            let count = result.level.features.filter { $0.kind == kind }.count
            return count > 0 ? "\(count) \(kind.rawValue)\(count == 1 ? "" : "s")" : nil
        }.joined(separator: " · ")
    }
}
