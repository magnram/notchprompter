import AVFoundation
import Speech
import SwiftUI
import NotchPrompterKit

/// Prompter settings. `compact` is the popover under the gear button; otherwise the Settings window.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: ScriptLibrary = .shared
    var compact = false

    private static let locales: [(id: String, name: String)] = SFSpeechRecognizer.supportedLocales()
        .map { ($0.identifier, Locale.interface.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var automaticName: String {
        let id = VoiceListener.detectLocale(for: library.active?.text ?? "")
        return Locale.interface.localizedString(forIdentifier: id) ?? id
    }

    private var modeDescription: String {
        switch settings.recordingMode {
        case .camera: String(localized: "Films you with the camera and microphone.")
        case .screen: String(localized: "Records the screen with your voice. The prompter is left out while it's hidden from recordings.")
        case .both: String(localized: "Saves a movie from the camera and a second movie of the screen for each take. The prompter is left out while it's hidden from recordings.")
        }
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
                        Text(verbatim: "\(Int(settings.fontSize))").monospacedDigit().frame(width: 26, alignment: .trailing)
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
                    Picker(selection: $settings.recordingMode) {
                        Text("Camera", comment: "Recording mode: film yourself").tag(RecordingMode.camera)
                        Text("Screen", comment: "Recording mode: record the screen").tag(RecordingMode.screen)
                        Text("Camera and screen", comment: "Recording mode: both, in two movies").tag(RecordingMode.both)
                    } label: {
                        Text("Record")
                        Text(modeDescription)
                    }
                    if settings.recordingMode.usesCamera {
                        Picker("Camera", selection: $settings.cameraID) {
                            Text("Default").tag("")
                            ForEach(Recorder.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                        }
                        CameraPreviewSection(cameraID: settings.cameraID)
                        Toggle(isOn: $settings.showCameraPreview) {
                            Text("Show the camera while recording")
                            Text("A small preview beside the prompter. Drag it anywhere. It is never in screen recordings.")
                        }
                    }
                    LabeledContent {
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(Recorder.folder)
                        }
                        .fixedSize()
                    } label: {
                        Text("Takes are saved in Movies › NotchPrompter",
                             comment: "Use the Finder name of the Movies folder in this language")
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
