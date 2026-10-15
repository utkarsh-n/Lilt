import SwiftUI
import LiltCore

struct PlayHomeView: View {
    let records: [RunRecord]
    let play: (MazeLevel) -> Void
    let levels: () -> Void
    let create: () -> Void
    let collection: () -> Void
    let settings: () -> Void
    private var nextLevel: MazeLevel {
        Campaign.levels.first { level in !records.contains { $0.mazeID == level.id } } ?? Campaign.levels[0]
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    HStack { CabinetScrew(); Spacer(); Button("Settings", systemImage: "gearshape.fill", action: settings)
                        .labelStyle(.iconOnly).buttonStyle(MetalButtonStyle(compact: true)).accessibilityIdentifier("settings"); Spacer(); CabinetScrew() }
                    VStack(spacing: 0) {
                        Text("LILT").font(.system(size: 72, weight: .black, design: .rounded)).tracking(7)
                            .foregroundStyle(LiltTheme.ink).shadow(color: .white.opacity(0.45), radius: 0, y: 2)
                            .accessibilityAddTraits(.isHeader)
                        Text("THE TILT MAZE").font(.system(.caption, weight: .heavy)).tracking(4).foregroundStyle(LiltTheme.ink.opacity(0.8))
                    }
                    MazePreview(level: Campaign.levels[3])
                        .frame(height: min(235, geometry.size.height * 0.30))
                        .rotationEffect(.degrees(-5))
                        .shadow(color: .black.opacity(0.4), radius: 7, x: 3, y: 7)
                        .padding(.vertical, 6)
                        .accessibilityHidden(true)
                    VStack(spacing: 12) {
                        LiltPrimaryButton(title: records.isEmpty ? "Play" : "Continue", symbol: "play.fill") { play(nextLevel) }
                            .accessibilityIdentifier("startRolling")
                        LiltPrimaryButton(title: "Select level", symbol: "square.grid.3x3.fill", action: levels)
                            .accessibilityIdentifier("selectLevel")
                        LiltPrimaryButton(title: "Generative mode", symbol: "sparkles", action: create)
                            .accessibilityIdentifier("dreamLabyrinth")
                        LiltPrimaryButton(title: "My mazes", symbol: "folder.fill", action: collection)
                            .accessibilityIdentifier("myMazes")
                    }.frame(maxWidth: 330)
                    Text("Tilt. Roll. Reach the finish.").font(.system(.caption, weight: .semibold)).foregroundStyle(LiltTheme.ink)
                    HStack { CabinetScrew(); Spacer(); CabinetScrew() }
                }
                .padding(.horizontal, 26).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
        }
        .background { WoodSurface().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct LevelSelectView: View {
    let records: [RunRecord]
    let play: (MazeLevel) -> Void
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(spacing: 19) {
                HStack {
                    CabinetScrew(); Spacer()
                    VStack(spacing: 4) {
                        Text("CLASSIC").font(.title2.bold()).tracking(2)
                        Text("12 wooden labyrinths").font(.caption.weight(.semibold))
                    }; Spacer(); CabinetScrew()
                }.foregroundStyle(LiltTheme.ink).padding(18).classicPanel()
                LazyVGrid(columns: columns, spacing: 17) {
                    ForEach(Array(Campaign.levels.enumerated()), id: \.element.id) { index, level in
                        Button { play(level) } label: {
                            VStack(spacing: 7) {
                                MazePreview(level: level).allowsHitTesting(false)
                                HStack(spacing: 5) {
                                    Text(String(format: "%02d", index + 1)).font(.title3.bold().monospacedDigit())
                                    if records.contains(where: { $0.mazeID == level.id }) { Image(systemName: "checkmark.circle.fill").font(.caption) }
                                }
                                Text(level.title).font(.caption2.weight(.semibold)).lineLimit(2).frame(height: 29)
                            }.foregroundStyle(LiltTheme.ink).padding(8).classicPanel().contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel("Level \(index + 1), \(level.title), \(level.difficulty.title)")
                        .accessibilityIdentifier("campaign_\(index + 1)")
                    }
                }
            }.padding(18)
        }
        .background { WoodSurface().ignoresSafeArea() }
        .navigationTitle("Select level").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
