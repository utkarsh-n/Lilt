import SwiftUI
import OfflineIntelligence

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("soundEnabled") private var sound = true
    @AppStorage("hapticsEnabled") private var haptics = true
    @AppStorage("preferTouch") private var preferTouch = false
    @AppStorage("showGhost") private var ghost = true
    @AppStorage("sensitivity") private var sensitivity = 1.3
    @AppStorage(OfflineModelChoice.preferenceKey) private var modelChoice = OfflineModelChoice.defaultChoice.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Feedback").font(.headline)
                        Toggle("Sound", isOn: $sound)
                        Divider()
                        Toggle("Haptics", isOn: $haptics)
                        Divider()
                        Toggle("Best-run ghost", isOn: $ghost)
                    }
                    .padding(18)
                    .classicPanel()

                    VStack(alignment: .leading, spacing: 15) {
                        Text("Controls").font(.headline)
                        Toggle("Prefer touch steering", isOn: $preferTouch)
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("Tilt sensitivity"); Spacer(); Text(String(format: "%.1f×", sensitivity)).monospacedDigit().foregroundStyle(LiltTheme.muted) }
                            Slider(value: $sensitivity, in: 0.6...2.4, step: 0.1)
                                .accessibilityLabel("Tilt sensitivity")
                        }.padding(.vertical, 5)
                        Text("Hold your iPhone comfortably, then calibrate during play. Touch steering uses the same marble physics. Lilt pauses when you leave the app.")
                            .font(.caption).foregroundStyle(LiltTheme.muted)
                    }
                    .padding(18)
                    .classicPanel()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Offline maze model").font(.headline)
                        Picker("Model", selection: $modelChoice) {
                            ForEach(OfflineModelChoice.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("offlineModelChoice")
                        Text("2B is the default and uses less memory. 4B is optional. Both interpret descriptions on this iPhone; the maze generator checks the route and preserves your explicit counts.")
                            .font(.caption).foregroundStyle(LiltTheme.muted)
                    }.padding(18).classicPanel()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("About Lilt").font(.headline)
                        Text("An original marble labyrinth, inspired by the classic wooden toy and the early iPhone tilt games.")
                        Text("Generative mode supports winding paths, spirals, gardens, and pinball boards, with holes, bumpers, magnets, and fans.")
                        Text("Mazes and best runs stay on this iPhone. The shared Qwen model interprets descriptions offline; a local interpreter builds a version if model files or a valid response are unavailable.")
                    }
                    .font(.subheadline)
                    .padding(18)
                    .classicPanel()
                }
                .foregroundStyle(LiltTheme.ink)
                .padding(18)
            }
            .background { WoodSurface() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(MetalButtonStyle(compact: true)) } }
        }
        .tint(LiltTheme.green)
    }
}
