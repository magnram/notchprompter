import Foundation
import Combine

/// User preferences, saved in UserDefaults. SwiftUI views and the prompter both observe this.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let speedRange: ClosedRange<Double> = 5...200
    static let fontSizeRange: ClosedRange<Double> = 12...60
    static let widthRange: ClosedRange<Double> = 260...1000
    static let heightRange: ClosedRange<Double> = 100...600
    /// `voiceLanguage` value that means "detect from the script".
    static let automaticLanguage = "auto"

    private let defaults = UserDefaults.standard

    /// Scroll speed for play mode, in points per second.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var width: Double { didSet { defaults.set(width, forKey: "width") } }
    @Published var height: Double { didSet { defaults.set(height, forKey: "height") } }
    /// Pause play mode while the mouse is over the prompter.
    @Published var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, forKey: "pauseOnHover") } }
    /// Count down 3-2-1 before play mode starts scrolling.
    @Published var countdown: Bool { didSet { defaults.set(countdown, forKey: "countdown") } }
    /// A speech locale such as "en-US", or `automaticLanguage`.
    @Published var voiceLanguage: String { didSet { defaults.set(voiceLanguage, forKey: "voiceLanguage") } }
    /// Keep the prompter out of screen sharing, screenshots and recordings.
    @Published var hideFromScreenSharing: Bool {
        didSet { defaults.set(hideFromScreenSharing, forKey: "hideFromScreenSharing") }
    }
    /// Camera for recordings (`AVCaptureDevice.uniqueID`); empty means the default camera.
    @Published var cameraID: String { didSet { defaults.set(cameraID, forKey: "cameraID") } }
    /// What a take records: the camera, the screen, or both, each into its own movie.
    @Published var recordingMode: RecordingMode { didSet { defaults.set(recordingMode.rawValue, forKey: "recordingMode") } }
    /// Show a small camera preview beside the prompter during a take.
    @Published var showCameraPreview: Bool { didSet { defaults.set(showCameraPreview, forKey: "showCameraPreview") } }
    /// Only use speech recognition that runs on this Mac (never Apple's servers).
    @Published var onDeviceOnly: Bool { didSet { defaults.set(onDeviceOnly, forKey: "onDeviceOnly") } }
    @Published var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    private init() {
        let d = UserDefaults.standard
        func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            (d.object(forKey: key) as? Double ?? fallback).clamped(to: range)
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

        speed = number("speed", 30, Self.speedRange)
        fontSize = number("fontSize", 20, Self.fontSizeRange)
        width = number("width", 440, Self.widthRange)
        height = number("height", 150, Self.heightRange)
        pauseOnHover = flag("pauseOnHover", true)
        countdown = flag("countdown", true)
        voiceLanguage = d.string(forKey: "voiceLanguage") ?? Self.automaticLanguage
        hideFromScreenSharing = flag("hideFromScreenSharing", true)
        cameraID = d.string(forKey: "cameraID") ?? ""
        // Before 1.1 there was only "Also record the screen", next to the camera.
        recordingMode = d.string(forKey: "recordingMode").flatMap(RecordingMode.init)
            ?? (flag("recordScreen", false) ? .both : .camera)
        showCameraPreview = flag("showCameraPreview", true)
        onDeviceOnly = flag("onDeviceOnly", true)
        hasSeenWelcome = flag("hasSeenWelcome", false)
    }
}

enum RecordingMode: String, CaseIterable {
    case camera, screen, both
    var usesCamera: Bool { self != .screen }
    var usesScreen: Bool { self != .camera }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
