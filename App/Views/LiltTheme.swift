import SwiftUI
import LiltCore

enum LiltTheme {
    static let paper = Color(red: 0.91, green: 0.79, blue: 0.59)
    static let ink = Color(red: 0.22, green: 0.15, blue: 0.09)
    static let green = Color(red: 0.40, green: 0.26, blue: 0.12)
    static let muted = Color(red: 0.42, green: 0.32, blue: 0.22)
    static let line = Color(red: 0.60, green: 0.45, blue: 0.27).opacity(0.5)
    static let serif = Font.system(.largeTitle, weight: .bold)
}

/// Original procedural grain; the cabinet uses no assets from another game.
struct WoodSurface: View {
    var light = false
    var body: some View {
        ZStack {
            LinearGradient(colors: light ? [Color(red: 0.96, green: 0.87, blue: 0.70), LiltTheme.paper] :
                [Color(red: 0.72, green: 0.49, blue: 0.27), Color(red: 0.83, green: 0.63, blue: 0.38), Color(red: 0.64, green: 0.41, blue: 0.21)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                for index in 0..<135 {
                    let x = CGFloat(index) * size.width / 135
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addCurve(to: CGPoint(x: x + sin(Double(index) * 0.79) * 5, y: size.height),
                        control1: CGPoint(x: x + sin(Double(index) * 0.37) * 12, y: size.height * 0.32),
                        control2: CGPoint(x: x - cos(Double(index) * 0.53) * 10, y: size.height * 0.7))
                    context.stroke(path, with: .color(Color(red: 0.28, green: 0.14, blue: 0.05).opacity(index % 5 == 0 ? 0.13 : 0.055)), lineWidth: index % 7 == 0 ? 1.3 : 0.5)
                }
            }
            LinearGradient(colors: [.black.opacity(0.14), .clear, .clear, .black.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct CabinetScrew: View {
    var body: some View {
        Circle().fill(LinearGradient(colors: [.white.opacity(0.95), Color(white: 0.48), Color(white: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Capsule().fill(.black.opacity(0.6)).frame(width: 8, height: 1.5).rotationEffect(.degrees(-35)) }
            .overlay { Circle().stroke(.black.opacity(0.4), lineWidth: 0.8) }
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
            .frame(width: 12, height: 12).accessibilityHidden(true)
    }
}

struct ClassicPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.background { WoodSurface(light: true) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.27), lineWidth: 1) }
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }
}

extension View {
    func classicPanel() -> some View { modifier(ClassicPanel()) }
}

struct MetalButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .subheadline : .headline, weight: .bold))
            .foregroundStyle(Color(white: 0.18))
            .shadow(color: .white.opacity(0.85), radius: 0, y: 1)
            .padding(.horizontal, compact ? 12 : 17)
            .padding(.vertical, compact ? 9 : 13)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(stops: [
                    .init(color: Color(white: configuration.isPressed ? 0.61 : 0.96), location: 0),
                    .init(color: Color(white: 0.78), location: 0.47),
                    .init(color: Color(white: 0.65), location: 0.5),
                    .init(color: Color(white: 0.86), location: 1)
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color(white: 0.25), lineWidth: 1) }
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.5), lineWidth: 1).padding(1.5) }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.35), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(enabled ? 1 : 0.48)
    }
}

extension MazeTheme {
    var title: String { switch self { case .oak: "Maple"; case .jade: "Jade"; case .midnight: "Midnight" } }
    var swatch: Color { switch self { case .oak: Color(red: 0.78, green: 0.62, blue: 0.40); case .jade: Color(red: 0.14, green: 0.34, blue: 0.28); case .midnight: Color(red: 0.18, green: 0.23, blue: 0.31) } }
}

extension MazeDifficulty {
    var title: String { switch self { case .easy: "Gentle"; case .medium: "Tricky"; case .hard: "Expert" } }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(.caption, weight: .bold)).tracking(1.3).foregroundStyle(LiltTheme.muted)
    }
}

struct LiltPrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: symbol); Text(title); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()) }
        }.buttonStyle(MetalButtonStyle())
    }
}

struct MazePreview: View {
    let level: MazeLevel
    @State private var source: StaticBoardSource
    @State private var renderError: String?
    init(level: MazeLevel) {
        self.level = level
        _source = State(initialValue: StaticBoardSource(level: level))
    }
    var body: some View {
        Group {
            if let renderError {
                ContentUnavailableView("Board unavailable", systemImage: "cube", description: Text(renderError))
            } else {
                BoardMetalView(source: source, running: false, redrawKey: 0) { renderError = $0 }
            }
        }
        .aspectRatio(level.width / level.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.4), lineWidth: 1) }
        .accessibilityLabel("Preview of \(level.title), \(level.difficulty.title), \(level.holes.count) holes")
        .id(level.id)
        .onChange(of: level.id) { _, _ in
            source = StaticBoardSource(level: level)
            renderError = nil
        }
    }
}
