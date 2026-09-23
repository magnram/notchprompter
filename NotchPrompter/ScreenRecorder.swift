import AppKit
import ScreenCaptureKit

/// Records the screen the prompter is on into a movie, next to the camera take or on its own.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, SCStreamOutput {
    /// Called on the main thread when the screen movie is saved (or failed).
    var onFinished: (_ url: URL?, _ problem: String?) -> Void = { _, _ in }
    private(set) var isRecording = false
    private(set) var startedAt = Date()
    /// The microphone audio, for voice-follow, when the screen is recorded with the microphone.
    var onAudio: ((CMSampleBuffer) -> Void)?
    private let audioQueue = DispatchQueue(label: "com.magnusramm.NotchPrompter.screen.audio")

    private var stream: SCStream?
    private var recording: SCRecordingOutput?
    private var url: URL?
    private var stopCompletion: (() -> Void)?

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Screen recording access. Asking shows the system prompt the first time; macOS may need
    /// the app to be reopened after access is turned on.
    static func requestAccess() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    /// Start capturing `screen` without saving yet. `hiddenWindows` are left out of the movie.
    /// With `microphone`, the movie gets the microphone's sound too (when there is no camera take).
    func prepare(screen: NSScreen?, hiddenWindows: [Int], microphone: Bool, ready: @escaping (String?) -> Void) {
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let scale = screen?.backingScaleFactor ?? 2
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
                else { throw ScreenError.noDisplay }
                let hidden = content.windows.filter { hiddenWindows.contains(Int($0.windowID)) }
                let filter = SCContentFilter(display: display, excludingWindows: hidden)
                let config = SCStreamConfiguration()
                config.width = Int(CGFloat(display.width) * scale)
                config.height = Int(CGFloat(display.height) * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.showsCursor = true
                config.queueDepth = 6
                config.captureMicrophone = microphone
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                if microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue) }
                try await stream.startCapture()
                await MainActor.run { self.stream = stream; ready(nil) }
            } catch {
                log.error("screen recorder: \(error.localizedDescription)")
                let problem = String(localized: "Couldn't record the screen: \(error.localizedDescription)",
                                     comment: "The placeholder is the system's error message")
                await MainActor.run { ready(problem) }
            }
        }
    }

    /// Start saving to Movies › NotchPrompter › `name`.mov (after `prepare`).
    func record(name: String) {
        guard let stream, !isRecording else { return }
        let url = Recorder.folder.appendingPathComponent(name + ".mov")
        let config = SCRecordingOutputConfiguration()
        config.outputURL = url
        config.outputFileType = .mov
        config.videoCodecType = .h264
        let recording = SCRecordingOutput(configuration: config, delegate: self)
        self.recording = recording
        self.url = url
        isRecording = true
        startedAt = Date()
        // Adding the output can take a moment; don't hold up the prompter while it does.
        DispatchQueue.global(qos: .userInitiated).async {
            do { try stream.addRecordingOutput(recording) }
            catch {
                self.finish(problem: String(localized: "Couldn't record the screen: \(error.localizedDescription)",
                                            comment: "The placeholder is the system's error message"))
            }
        }
    }

    /// Stop saving and stop capturing. `completion` runs when the movie is finished.
    func stop(completion: (() -> Void)? = nil) {
        guard let stream else { completion?(); return }
        self.stream = nil
        if let recording, isRecording {
            // Stop capturing only after the file is finished, or its last frames are lost.
            stopCompletion = { completion?(); Task { try? await stream.stopCapture() } }
            do { try stream.removeRecordingOutput(recording) }   // finishes the file, then calls the delegate
            catch {
                finish(problem: String(localized: "The screen recording couldn't be saved: \(error.localizedDescription)",
                                       comment: "The placeholder is the system's error message"))
            }
        } else {
            completion?()
            Task { try? await stream.stopCapture() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .microphone { onAudio?(sampleBuffer) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(problem: nil)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(problem: String(localized: "The screen recording couldn't be saved: \(error.localizedDescription)",
                               comment: "The placeholder is the system's error message"))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("screen stream stopped: \(error.localizedDescription)")
        if isRecording {
            finish(problem: String(localized: "Screen recording stopped: \(error.localizedDescription)",
                                   comment: "The placeholder is the system's error message"))
        }
    }

    private func finish(problem: String?) {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            self.isRecording = false
            self.recording = nil
            self.onFinished(problem == nil ? self.url : nil, problem)
            self.stopCompletion?()
            self.stopCompletion = nil
        }
    }

    private enum ScreenError: LocalizedError {
        case noDisplay
        var errorDescription: String? { String(localized: "No screen found.") }
    }
}
