import Foundation
import Combine

/// User preferences, saved in UserDefaults. SwiftUI views and the prompter both observe this.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    public static let speedRange: ClosedRange<Double> = 5...200
    public static let fontSizeRange: ClosedRange<Double> = 12...60
    public static let widthRange: ClosedRange<Double> = 260...1000
    public static let heightRange: ClosedRange<Double> = 100...600
    /// `voiceLanguage` value that means "detect from the script".
    public static let automaticLanguage = "auto"

    private let defaults = UserDefaults.standard

    /// Scroll speed for play mode, in points per second.
    @Published public var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published public var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published public var width: Double { didSet { defaults.set(width, forKey: "width") } }
    @Published public var height: Double { didSet { defaults.set(height, forKey: "height") } }
    /// Pause play mode while the mouse is over the prompter.
    @Published public var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, forKey: "pauseOnHover") } }
    /// Count down 3-2-1 before play mode starts scrolling.
    @Published public var countdown: Bool { didSet { defaults.set(countdown, forKey: "countdown") } }
    /// A speech locale such as "en-US", or `automaticLanguage`.
    @Published public var voiceLanguage: String { didSet { defaults.set(voiceLanguage, forKey: "voiceLanguage") } }
    /// Keep the prompter out of screen sharing, screenshots and recordings.
    @Published public var hideFromScreenSharing: Bool {
        didSet { defaults.set(hideFromScreenSharing, forKey: "hideFromScreenSharing") }
    }
    /// Camera for recordings (`AVCaptureDevice.uniqueID`); empty means the default camera.
    @Published public var cameraID: String { didSet { defaults.set(cameraID, forKey: "cameraID") } }
    /// What a take records: the camera, the screen, or both, each into its own movie.
    @Published public var recordingMode: RecordingMode { didSet { defaults.set(recordingMode.rawValue, forKey: "recordingMode") } }
    /// Show a small camera preview beside the prompter during a take.
    @Published public var showCameraPreview: Bool { didSet { defaults.set(showCameraPreview, forKey: "showCameraPreview") } }
    /// Only use speech recognition that runs on this Mac (never Apple's servers).
    @Published public var onDeviceOnly: Bool { didSet { defaults.set(onDeviceOnly, forKey: "onDeviceOnly") } }
    @Published public var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    private init() {
        let d = UserDefaults.standard
        func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            (d.object(forKey: key) as? Double ?? fallback).clamped(to: range)
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

        speed = number("speed", 30, Self.speedRange)
        #if os(iOS)
        fontSize = number("fontSize", 28, Self.fontSizeRange)
        #else
        fontSize = number("fontSize", 20, Self.fontSizeRange)
        #endif
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

public enum RecordingMode: String, CaseIterable {
    case camera, screen, both
    public var usesCamera: Bool { self != .screen }
    public var usesScreen: Bool { self != .camera }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
