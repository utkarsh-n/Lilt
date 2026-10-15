import SwiftUI
import SwiftData
import LiltCore

struct GameView: View {
    let level: MazeLevel
    let previousRecord: RunRecord?
    let next: (MazeLevel) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: GameSession
    @State private var renderError: String?
    @State private var storageError: String?
    @State private var newBest = false
    @State private var bestTime: Double?
    @State private var helpPresented = false
    @AppStorage("soundEnabled") private var sound = true
    @AppStorage("hapticsEnabled") private var haptics = true
    @AppStorage("preferTouch") private var preferTouch = false
    @AppStorage("showGhost") private var ghost = true
    @AppStorage("sensitivity") private var sensitivity = 1.3

    init(level: MazeLevel, previousRecord: RunRecord?, next: @escaping (MazeLevel) -> Void) {
        self.level = level
        self.previousRecord = previousRecord
        self.next = next
        _session = State(initialValue: GameSession(level: level, previousReplay: previousRecord?.replay ?? []))
        _bestTime = State(initialValue: previousRecord?.time)
    }

    var body: some View {
        VStack(spacing: 7) {
            header
            board.layoutPriority(1)
            if session.touchControl {
                HStack(spacing: 18) {
                    SteeringPad(enabled: session.isRunning, setTilt: session.setTouchTilt, nudge: session.nudge)
                        .frame(width: 94, height: 94)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("TOUCH STEERING").font(.caption2.bold()).tracking(1)
                        Text("Drag gently. Reverse to brake.").font(.caption)
                        controls
                    }.foregroundStyle(LiltTheme.ink)
                }.padding(.horizontal, 15)
            } else {
                controls.padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WoodSurface().ignoresSafeArea() }
        .preferredColorScheme(.light)
        .onAppear(perform: configure)
        .onDisappear { session.pause(); session.onWin = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.pause() } }
        .sheet(isPresented: $helpPresented) { help }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button("Menu", systemImage: "chevron.left") { session.pause(); dismiss() }
                .labelStyle(.iconOnly).buttonStyle(MetalButtonStyle(compact: true))
                .accessibilityIdentifier("closeGame")
            VStack(alignment: .leading, spacing: 2) {
                Text(levelNumber).font(.system(.caption, weight: .black)).tracking(1)
                Text(level.title).font(.caption2.weight(.semibold)).lineLimit(1)
            }.foregroundStyle(LiltTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%05.1f", session.displayedTime))
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.80, green: 0.86, blue: 0.71))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color(red: 0.18, green: 0.21, blue: 0.17), in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.7), lineWidth: 1) }
                .accessibilityLabel(String(format: "Time %.1f seconds", session.displayedTime))
            Button(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                if session.isPaused { session.resume() } else { session.pause() }
            }.labelStyle(.iconOnly).buttonStyle(MetalButtonStyle(compact: true))
                .disabled(!session.hasStarted || session.status == .won).accessibilityIdentifier("pauseGame")
        }.padding(.horizontal, 3)
    }

    private var levelNumber: String {
        if let index = Campaign.levels.firstIndex(where: { $0.id == level.id }) { return String(format: "LEVEL %02d", index + 1) }
        return "MY MAZE"
    }

    private var board: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * level.width / level.height)
            ZStack {
                if let renderError {
                    ContentUnavailableView("Metal board unavailable", systemImage: "cube", description: Text(renderError))
                } else {
                    BoardMetalView(source: session, running: session.isRunning,
                        redrawKey: session.attempts * 2 + (session.showRoute ? 1 : 0)) { renderError = $0 }
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
                        .accessibilityElement()
                        .accessibilityLabel("Labyrinth board. \(level.holes.count) trap holes. Use tilt or the steering controls to reach the checkered finish.")
                        .accessibilityIdentifier("gameBoard")
                }
                if !session.hasStarted { readyCard }
                else if session.status == .won { winCard }
                else if session.isPaused && !helpPresented { pauseCard }
            }
            .frame(width: width, height: width * level.height / level.width)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }.frame(minHeight: 220)
    }

    private var readyCard: some View {
        VStack(spacing: 17) {
            Text(levelNumber).font(.caption.bold()).tracking(2)
            Text("Ready?").font(.largeTitle.bold())
            Image(systemName: session.touchControl ? "hand.draw" : "iphone.gen3.radiowaves.left.and.right").font(.system(size: 34))
            Text(session.touchControl ? "Drag the pad to roll the marble.\nReach the checkered finish." : "Hold your iPhone comfortably.\nTilt to roll the marble to the finish.")
                .font(.subheadline).multilineTextAlignment(.center)
            Button("Play", systemImage: "play.fill") { session.start() }
                .buttonStyle(MetalButtonStyle()).accessibilityIdentifier("beginGame")
        }.padding(26).frame(maxWidth: 300).foregroundStyle(LiltTheme.ink).classicPanel().padding(18)
    }

    private var pauseCard: some View {
        VStack(spacing: 15) {
            Text("Paused").font(.title.bold())
            if let bestTime { Text(String(format: "Best time: %.1f seconds", bestTime)).font(.caption.monospacedDigit()) }
            Button("Resume", systemImage: "play.fill") { session.resume() }
                .buttonStyle(MetalButtonStyle()).accessibilityIdentifier("resumeGame")
            Button("Restart", systemImage: "arrow.counterclockwise") { newBest = false; session.restart() }
                .buttonStyle(MetalButtonStyle(compact: true))
            Button("Main menu") { session.pause(); dismiss() }.buttonStyle(MetalButtonStyle(compact: true))
        }.padding(25).frame(maxWidth: 290).foregroundStyle(LiltTheme.ink).classicPanel().padding(18)
    }

    private var winCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "flag.pattern.checkered").font(.system(size: 34))
            Text("Level complete!").font(.title2.bold())
            Text(String(format: "%.1f seconds", session.displayedTime)).font(.title.monospacedDigit())
            Text(session.usedHint ? "Guided run · try without the route" : newBest ? "New best time!" : "Well played!")
                .font(.caption.bold()).multilineTextAlignment(.center)
            if let nextLevel {
                Button("Next level", systemImage: "arrow.right") { session.pause(); next(nextLevel) }
                    .buttonStyle(MetalButtonStyle())
            }
            Button("Play again", systemImage: "arrow.counterclockwise") { newBest = false; session.restart() }
                .buttonStyle(MetalButtonStyle(compact: true)).accessibilityIdentifier("rollAgain")
            Button("Main menu") { session.pause(); dismiss() }.buttonStyle(MetalButtonStyle(compact: true))
            if let storageError { Text(storageError).font(.caption2).foregroundStyle(.red) }
        }.padding(23).frame(maxWidth: 305).foregroundStyle(LiltTheme.ink).classicPanel().padding(18)
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Button("Restart", systemImage: "arrow.counterclockwise") { newBest = false; session.restart() }
                .labelStyle(.iconOnly).buttonStyle(MetalButtonStyle(compact: true)).accessibilityIdentifier("restartGame")
            Spacer(minLength: 0)
            Text(session.status == .falling ? "TRY AGAIN" : "ATTEMPT \(session.attempts)")
                .font(.caption2.bold()).foregroundStyle(LiltTheme.ink).tracking(1)
            Spacer(minLength: 0)
            if !session.touchControl {
                Button("Calibrate", systemImage: "scope") { session.calibrate() }
                    .labelStyle(.iconOnly).buttonStyle(MetalButtonStyle(compact: true)).accessibilityIdentifier("calibrateGame")
            }
            Button("How to play", systemImage: "questionmark") { session.pause(); helpPresented = true }
                .labelStyle(.iconOnly).buttonStyle(MetalButtonStyle(compact: true))
        }
    }

    private var help: some View {
        NavigationStack {
            Form {
                Section("How to play") {
                    Text("Tilt to accelerate the marble. Level the phone to slow down; tilt the other way to brake. The ball carries momentum through each turn.")
                    Text("Avoid the black holes and reach the checkered finish. Falls restart the same board.")
                    Text("Bumpers kick the marble away. Magnets pull it closer. Fans push in the direction of their blades.")
                }
                Section("Controls") {
                    Toggle("Touch steering", isOn: $session.touchControl).disabled(!session.motionAvailable)
                    Text("Drag the pad to steer with force. The four arrows make short nudges and work with VoiceOver.")
                    Toggle("Show route", isOn: $session.showRoute).accessibilityIdentifier("showRoute")
                    Text("Guided runs don't replace your best time.")
                }
            }
            .navigationTitle("How to play").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { helpPresented = false } } }
        }.tint(LiltTheme.green)
    }

    private var nextLevel: MazeLevel? {
        guard let index = Campaign.levels.firstIndex(where: { $0.id == level.id }), index + 1 < Campaign.levels.count else { return nil }
        return Campaign.levels[index + 1]
    }

    private func configure() {
        session.touchControl = preferTouch || !session.motionAvailable
        session.sensitivity = sensitivity
        session.showGhost = ghost && !reduceMotion
        session.feedback.soundEnabled = sound
        session.feedback.hapticsEnabled = haptics
        session.prepareControls()
        session.onWin = { [weak session] time, replay in
            guard let session, !session.usedHint else { return }
            do {
                if try RunPersistence.saveBest(mazeID: level.id, time: time, replay: replay, context: modelContext) {
                    bestTime = time
                    session.installBestReplay(replay)
                    newBest = true
                }
            } catch {
                modelContext.rollback()
                storageError = "Couldn't save the best run. \(error.localizedDescription)"
            }
        }
    }
}

private struct SteeringPad: View {
    let enabled: Bool
    let setTilt: (Vec2) -> Void
    let nudge: (Vec2) -> Void
    @State private var offset = CGSize.zero

    var body: some View {
        ZStack {
            Circle().fill(LiltTheme.green.opacity(0.065))
                .overlay { Circle().stroke(LiltTheme.green.opacity(0.18), lineWidth: 1) }
            Circle().stroke(LiltTheme.green.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [2, 4])).padding(19)
            Image(systemName: "plus").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(LiltTheme.green.opacity(0.18))
            Circle().fill(LiltTheme.green).frame(width: 27, height: 27)
                .overlay { Circle().stroke(.white.opacity(0.35), lineWidth: 1).padding(3) }
                .shadow(color: LiltTheme.green.opacity(0.18), radius: 5, y: 3)
                .offset(offset)
                .accessibilityHidden(true)
            // Native buttons provide an alternative to dragging and expose directional actions.
            VStack {
                arrow("Roll up", "chevron.up", Vec2(0, -1))
                Spacer(minLength: 0)
                arrow("Roll down", "chevron.down", Vec2(0, 1))
            }
            HStack {
                arrow("Roll left", "chevron.left", Vec2(-1, 0))
                Spacer(minLength: 0)
                arrow("Roll right", "chevron.right", Vec2(1, 0))
            }
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 8).onChanged { value in
            guard enabled else { return }
            let vector = Vec2(value.translation.width / 42, value.translation.height / 42)
            let normalized = vector.length > 1 ? vector.normalized : vector
            offset = CGSize(width: normalized.x * 29, height: normalized.y * 29)
            setTilt(normalized * 0.65)
        }.onEnded { _ in offset = .zero; setTilt(.zero) })
        .opacity(enabled ? 1 : 0.5)
        .onChange(of: enabled) { _, value in if !value { offset = .zero; setTilt(.zero) } }
        .accessibilityIdentifier("steeringPad")
    }

    private func arrow(_ label: String, _ symbol: String, _ direction: Vec2) -> some View {
        Button { nudge(direction) } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .medium))
                .foregroundStyle(LiltTheme.green.opacity(0.65)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
        .accessibilityIdentifier(label.replacingOccurrences(of: " ", with: ""))
    }
}
