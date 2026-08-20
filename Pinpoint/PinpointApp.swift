import SwiftUI
import KeyboardShortcuts

// Default global shortcuts: ⌘⇧1 capture, ⌘⇧2 étagère.
extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.one, modifiers: [.command, .shift]))
    static let openShelf = Self("openShelf", default: .init(.two, modifiers: [.command, .shift]))
}

@main
struct PinpointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar only app (LSUIElement = true). The Settings scene gives us a
        // standard ⌘, preferences window without forcing a main window open.
        Settings {
            SettingsView()
        }
    }
}

/// Fenêtre Réglages unifiée : onglet Capture (raccourci, repères, partage agent)
/// et onglet Étagère (dossier surveillé, lancement au démarrage). Les deux
/// onglets pilotent le même `ScreenshotStore` partagé que la fenêtre Étagère.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                CaptureSettingsView()
                    .tabItem { Label("Capture", systemImage: "camera.viewfinder") }

                ShelfSettingsView()
                    .environmentObject(ScreenshotStore.shared)
                    .tabItem { Label("Shelf", systemImage: "tray.full") }
            }

            Divider()
            Text(Self.versionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 6)
        }
        .frame(width: 460, height: 520)
    }

    /// Marketing version + build read from the bundle, e.g. "Pinpoint 0.3.0 (3)".
    /// Selectable so it can be copied into a bug report.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Pinpoint \(short) (\(build))"
    }
}

struct CaptureSettingsView: View {
    @AppStorage(PinStyle.storageKey) private var pinStyle: PinStyle = .disc
    @AppStorage("includeLegend") private var includeLegend = true
    @AppStorage(AgentTextFormat.storageKey) private var textFormat: AgentTextFormat = .markdown
    @AppStorage(CaptureDelay.storageKey) private var captureDelay: CaptureDelay = .off
    @AppStorage(AXContextSettings.enabledKey) private var axContext = true
    @AppStorage(AXContextSettings.fieldValuesKey) private var axFieldValues = false
    @AppStorage(TextRecognitionSettings.enabledKey) private var textRecognition = true

    /// Whether macOS grants Accessibility, re-read whenever the window comes
    /// back — the switch is flipped in System Settings, in another process, so
    /// there's nothing to observe here beyond "the user came back to us".
    @State private var isTrusted = AXPermission.isTrusted

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder(String(localized: "Capture screen:"), name: .capture)
                KeyboardShortcuts.Recorder(String(localized: "Open shelf:"), name: .openShelf)
            }
            Section("Marker style") {
                Picker("Style:", selection: $pinStyle) {
                    ForEach(PinStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text(pinStyle.caption)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Section("Capture timer") {
                Picker("Delay before capture:", selection: $captureDelay) {
                    ForEach(CaptureDelay.allCases) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
                Text("Pause before the screenshot so you can arrange UI elements or open a menu.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Section("Agent sharing") {
                Toggle("Embed legend in the image", isOn: $includeLegend)
                Text("Adds the marker descriptions and instructions below the capture so a single paste carries everything to the agent.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Picker(String(localized: "settings.format.label",
                              defaultValue: "Copied text:"), selection: $textFormat) {
                    ForEach(AgentTextFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                // Nothing to choose while the legend is embedded: the image then
                // carries everything and the clipboard deliberately holds no
                // text at all, since a terminal pastes the string and drops the
                // picture when both share an item.
                .disabled(includeLegend)
                Text(includeLegend
                     ? String(localized: "settings.format.unused",
                              defaultValue: "Unavailable while the legend is embedded: the clipboard then carries the image alone. The files for the agent are written in both formats either way.")
                     : String(localized: "settings.format.explanation",
                              defaultValue: "Markdown reads well when pasted into a conversation; JSON is the same facts in the versioned contract, for a script that indexes them. Both are always written to the files for the agent."))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            accessibilitySection
            textRecognitionSection
        }
        .formStyle(.grouped)
        // Coming back from System Settings is the moment the answer can have
        // changed; nothing else in this window can change it.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = AXPermission.isTrusted
        }
    }

    /// The accessibility context (#55): what turns a marker from a pixel into a
    /// named element an agent can go and edit.
    ///
    /// Its permission is a separate grant from Screen Recording, so the section
    /// states where it stands rather than surprising anyone mid-capture — and
    /// nothing here prompts unless the button is pressed.
    private var accessibilitySection: some View {
        Section(String(localized: "settings.ax.section", defaultValue: "Interface context")) {
            Toggle(String(localized: "settings.ax.toggle",
                          defaultValue: "Describe the element under each marker"),
                   isOn: $axContext)
            Text(String(localized: "settings.ax.explanation",
                        defaultValue: "Adds a line under each marker naming the interface element it points at — its role, its label and the app owning it — read while the capture is taken. Needs the Accessibility permission, which is separate from Screen Recording."))
                .foregroundStyle(.secondary)
                .font(.callout)

            if axContext && !isTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "settings.ax.permission.missing",
                                defaultValue: "Accessibility permission required. Without it, captures work exactly as before — they just carry no interface details."))
                        .font(.callout)
                }
                Button(String(localized: "settings.ax.permission.grant",
                              defaultValue: "Allow access…")) {
                    AXPermission.request()
                    isTrusted = AXPermission.isTrusted
                }
            }

            Toggle(String(localized: "settings.ax.fieldValues",
                          defaultValue: "Include what is typed in fields"),
                   isOn: $axFieldValues)
                .disabled(!axContext)
            Text(String(localized: "settings.ax.fieldValues.explanation",
                        defaultValue: "Off by default: the accessibility tree returns the whole contents of a field, including the part scrolled out of the picture. Password fields are never read, whatever this says."))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    /// Reading the text in the capture (#49).
    ///
    /// Needs no permission and reaches no network, so unlike the section above
    /// there is nothing to prompt for and nothing to warn about. What the
    /// explanation has to be straight about instead is the change it makes:
    /// the text was always in the picture, and this puts it in the text files
    /// too — where it can be searched, quoted and pasted on, which is both the
    /// point of the feature and the reason someone might want it off.
    private var textRecognitionSection: some View {
        Section(String(localized: "settings.ocr.section", defaultValue: "Text in the capture")) {
            Toggle(String(localized: "settings.ocr.toggle",
                          defaultValue: "Read the text under each marker"),
                   isOn: $textRecognition)
            Text(String(localized: "settings.ocr.explanation",
                        defaultValue: "Pre-fills a marker’s description with the line of text it points at, and writes that line into the files for the agent — so small text an agent would misread from the image travels as text. Read on this Mac; nothing is sent anywhere. Areas you have hidden are never read."))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
