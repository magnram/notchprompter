import AVFoundation
import Speech
import SwiftUI

/// Prompter settings. `compact` is the popover under the gear button; otherwise the Settings window.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: ScriptLibrary = .shared
    var compact = false

    private static let locales: [(id: String, name: String)] = SFSpeechRecognizer.supportedLocales()
        .map { ($0.identifier, Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var automaticName: String {
        let id = VoiceListener.detectLocale(for: library.active?.text ?? "")
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    /// Whole numbers, without the tick marks a stepped slider draws.
    private func rounded(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() })
    }

    var body: some View {
        Form {
            if compact {
                Picker("Script", selection: $library.activeID) {
                    ForEach(library.scripts) { Text($0.displayTitle).tag(Optional($0.id)) }
                }
            }
            Section {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: rounded($settings.fontSize), in: AppSettings.fontSizeRange)
                        Text("\(Int(settings.fontSize))").monospacedDigit().frame(width: 26, alignment: .trailing)
                    }
                }
                Picker("Voice language", selection: $settings.voiceLanguage) {
                    Text("Automatic (\(automaticName))").tag(AppSettings.automaticLanguage)
                    Divider()
                    ForEach(Self.locales, id: \.id) { Text($0.name).tag($0.id) }
                }
            } header: {
                if !compact { Text("Reading") }
            }
            Section {
                LabeledContent("Play speed") {
                    HStack {
                        Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                        Slider(value: rounded($settings.speed), in: AppSettings.speedRange)
                        Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    }
                }
                Toggle("Pause while the mouse is over the text", isOn: $settings.pauseOnHover)
                Toggle("Count down 3-2-1 before scrolling", isOn: $settings.countdown)
            } header: {
                if !compact { Text("Play mode") }
            }
            if !compact {
                Section("Recording") {
                    Picker("Camera", selection: $settings.cameraID) {
                        Text("Default").tag("")
                        ForEach(Recorder.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    Toggle(isOn: $settings.recordScreen) {
                        Text("Also record the screen")
                        Text("Saves a second movie of your screen for each take. The prompter is left out while it's hidden from recordings.")
                    }
                    LabeledContent("Takes are saved in Movies › NotchPrompter") {
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(Recorder.folder)
                        }
                    }
                }
                Section("Privacy") {
                    Toggle("Hide the prompter from screen sharing and recordings", isOn: $settings.hideFromScreenSharing)
                    Toggle(isOn: $settings.onDeviceOnly) {
                        Text("Recognise speech on this Mac only")
                        Text("Your voice never leaves your Mac. Needs Dictation turned on in System Settings → Keyboard. Turn off to use Apple's servers instead.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: compact ? 340 : 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
