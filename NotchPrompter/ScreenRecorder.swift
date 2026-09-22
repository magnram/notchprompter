import AppKit
import ScreenCaptureKit

/// Records the screen the prompter is on into a movie, next to the camera take.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    /// Called on the main thread when the screen movie is saved (or failed).
    var onFinished: (_ url: URL?, _ problem: String?) -> Void = { _, _ in }
    private(set) var isRecording = false

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

    /// Start capturing `screen` without saving yet. `hiddenWindow` is left out of the movie.
    func prepare(screen: NSScreen?, hiddenWindow: Int?, ready: @escaping (String?) -> Void) {
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let scale = screen?.backingScaleFactor ?? 2
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
                else { throw ScreenError.noDisplay }
                let hidden = content.windows.filter { window in hiddenWindow.map { Int(window.windowID) == $0 } ?? false }
                let filter = SCContentFilter(display: display, excludingWindows: hidden)
                let config = SCStreamConfiguration()
                config.width = Int(CGFloat(display.width) * scale)
                config.height = Int(CGFloat(display.height) * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.showsCursor = true
                config.queueDepth = 6
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try await stream.startCapture()
                await MainActor.run { self.stream = stream; ready(nil) }
            } catch {
                log.error("screen recorder: \(error.localizedDescription)")
                await MainActor.run { ready("Couldn't record the screen: \(error.localizedDescription)") }
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
        // Adding the output can take a moment; don't hold up the prompter while it does.
        DispatchQueue.global(qos: .userInitiated).async {
            do { try stream.addRecordingOutput(recording) }
            catch { self.finish(problem: "Couldn't record the screen: \(error.localizedDescription)") }
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
            catch { finish(problem: "The screen recording couldn't be saved: \(error.localizedDescription)") }
        } else {
            completion?()
            Task { try? await stream.stopCapture() }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(problem: nil)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(problem: "The screen recording couldn't be saved: \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("screen stream stopped: \(error.localizedDescription)")
        if isRecording { finish(problem: "Screen recording stopped: \(error.localizedDescription)") }
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
        var errorDescription: String? { "No screen found." }
    }
}
