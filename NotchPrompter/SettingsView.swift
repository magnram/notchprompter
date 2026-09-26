import AVFoundation
import Speech
import SwiftUI
import NotchPrompterKit

/// Prompter settings. `compact` is the popover under the gear button; otherwise the Settings window.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: ScriptLibrary = .shared
    @ObservedObject var folder: ScriptFolder = .shared
    @ObservedObject var displays: Displays = .shared
    @ObservedObject var shortcuts: GlobalShortcuts = .shared
    var compact = false
    /// Opens the Settings window; the popover shows a link to it when set.
    var openAll: (() -> Void)?

    private static let locales: [(id: String, name: String)] = SFSpeechRecognizer.supportedLocales()
        .map { ($0.identifier, Locale.interface.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var automaticName: String {
        let id = VoiceListener.detectLocale(for: library.active?.text ?? "")
        return Locale.interface.localizedString(forIdentifier: id) ?? id
    }

    /// Whole numbers, without the tick marks a stepped slider draws.
    private func rounded(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() })
    }

    var body: some View {
        if compact {
            Form {
                Picker("Script", selection: $library.activeID) {
                    ForEach(library.scripts) { Text($0.displayTitle).tag(Optional($0.id)) }
                }
                reading
                if let openAll { AllSettingsLink(action: openAll) }
            }
            .formStyle(.grouped)
            .frame(width: 340)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // Tabs, so the window fits on a laptop screen.
            TabView {
                page {
                    reading
                    shortcutsSection
                    privacy
                }
                .tabItem { Label("General", systemImage: "gearshape") }
                page { RecordingSettings(settings: settings) }
                    .tabItem { Label("Recording", systemImage: "video") }
                page { scripts }
                    .tabItem { Label("Scripts", systemImage: "doc.text") }
            }
            .frame(width: 460)
        }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var reading: some View {
        Section {
            LabeledContent("Text size") {
                HStack {
                    Slider(value: rounded($settings.fontSize), in: AppSettings.fontSizeRange)
                    Text(verbatim: "\(Int(settings.fontSize))").monospacedDigit().frame(width: 26, alignment: .trailing)
                }
            }
            // Only with more than one screen, or to go back from one that isn't connected.
            if displays.all.count > 1 || !settings.display.isEmpty {
                Picker("Show on", selection: $settings.display) {
                    Text("Automatic (\(NSScreen.forPrompter("")?.localizedName ?? ""))").tag("")
                    Divider()
                    ForEach(displays.all) { Text(verbatim: $0.name).tag($0.id) }
                    if !settings.display.isEmpty, !displays.all.contains(where: { $0.id == settings.display }) {
                        Text("Not connected", comment: "A screen chosen for the prompter that isn't connected now").tag(settings.display)
                    }
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
    }

    private var scripts: some View {
        Section {
            LabeledContent {
                HStack {
                    if folder.url != nil {
                        Button("Stop") { folder.stop() }
                    }
                    Button(folder.url == nil ? String(localized: "Choose…") : String(localized: "Change…")) { folder.choose() }
                }
                .fixedSize()
            } label: {
                Text("Keep scripts as files in a folder")
                Text("Each script is a Markdown file you can edit in any app, or let an AI assistant such as Claude or Codex write. Changes show up right away.")
            }
            if folder.url != nil {
                LabeledContent {
                    Button("Show in Finder") { folder.reveal() }.fixedSize()
                } label: {
                    Text(verbatim: folder.displayPath)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private var shortcutsSection: some View {
        Section("Keyboard Shortcuts") {
            Toggle(isOn: $settings.globalShortcuts) {
                Text("Use these shortcuts in any app")
                Text("They work while a video call, Keynote or the app you record is in front.")
            }
            ForEach(GlobalShortcuts.Action.allCases, id: \.self) { action in
                LabeledContent(action.title) {
                    HStack {
                        if shortcuts.taken.contains(action) {
                            Text("Used by another app").foregroundStyle(.red)
                        }
                        Text(verbatim: action.keys).monospaced()
                    }
                }
                .disabled(!settings.globalShortcuts)
            }
        }
    }

    private var privacy: some View {
        Section("Privacy") {
            Toggle("Hide the prompter from screen sharing and recordings", isOn: $settings.hideFromScreenSharing)
            Toggle(isOn: $settings.onDeviceOnly) {
                Text("Recognise speech on this Mac only")
                Text("Your voice never leaves your Mac. Needs Dictation turned on in System Settings → Keyboard. Turn off to use Apple's servers instead.")
            }
        }
    }
}

/// The recording rows, in the Settings window and in the popover beside the record button.
struct RecordingSettings: View {
    @ObservedObject var settings: AppSettings

    private var modeDescription: String {
        switch settings.recordingMode {
        case .camera: String(localized: "Films you with the camera and microphone.")
        case .screen: String(localized: "Records the screen with your voice. The prompter is left out while it's hidden from recordings.")
        case .both: String(localized: "Saves a movie from the camera and a second movie of the screen for each take. The prompter is left out while it's hidden from recordings.")
        }
    }

    var body: some View {
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
        Picker("Microphone", selection: $settings.microphoneID) {
            Text("Default").tag("")
            ForEach(Recorder.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
        }
        MicrophoneLevelSection(microphoneID: settings.microphoneID)
        Toggle(isOn: $settings.saveTranscripts) {
            Text("Save a transcript with each take")
            Text("Subtitles (.srt) next to the movie, made on this Mac after the take. Use them for captions, or let an AI assistant check and cut the take.")
        }
        if settings.recordingMode == .camera {
            Picker(selection: $settings.screenLight) {
                Text("As it is", comment: "Screen light option: leave the screen as it is").tag(ScreenLight.off)
                Text("Soft light", comment: "Screen light option: fill the screen with warm white").tag(ScreenLight.light)
                Text("Black", comment: "Screen light option: fill the screen with black").tag(ScreenLight.dark)
            } label: {
                Text("Screen while recording")
                Text("Fills the rest of the screen during a take. Soft light lights up your face. Black stops glare in glasses and keeps the room dark. Turn the screen brightness up for more light.")
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
}

/// The popover beside the record button: check the camera and change how takes are filmed, without a take.
struct RecordingPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var lastTake: LastTake
    let play: () -> Void
    let trash: () -> Void
    let openAll: () -> Void

    var body: some View {
        Form {
            if let name = lastTake.name {
                Section("Last take") {
                    LabeledContent {
                        HStack {
                            Button("Play", action: play)
                            Button("Move to Trash", action: trash)
                        }
                        .fixedSize()
                    } label: {
                        Text(verbatim: name).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            RecordingSettings(settings: settings)
            AllSettingsLink(action: openAll)
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The last row of a popover: the Settings window has the rest.
private struct AllSettingsLink: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("All Settings…", action: action)
        }
    }
}
