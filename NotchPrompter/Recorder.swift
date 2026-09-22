import AVFoundation
import AppKit

/// Films the camera and microphone into a movie file in Movies › NotchPrompter.
final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Called on the main thread when a take is saved (or failed).
    var onFinished: (_ url: URL?, _ problem: String?) -> Void = { _, _ in }
    private(set) var isRecording = false
    private(set) var startedAt = Date()

    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    /// The same microphone audio, for voice-follow while recording (set before `start`).
    var onAudio: ((CMSampleBuffer) -> Void)?
    private let audioOutput = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "com.magnusramm.NotchPrompter.recorder.audio")
    private let queue = DispatchQueue(label: "com.magnusramm.NotchPrompter.recorder")
    private var stopCompletion: (() -> Void)?

    /// The real Movies folder. Inside the sandbox the home directory is the app's container,
    /// so look up the user's home instead (the app has the Movies folder entitlement).
    static var folder: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Movies/NotchPrompter", isDirectory: true)
    }

    static var cameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    static let cameraSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!

    /// Ask for camera and microphone access. `done` gets nil, or a message and where to fix it.
    static func requestAccess(_ done: @escaping ((message: String, url: URL)?) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { camera in
            guard camera else {
                return DispatchQueue.main.async {
                    done(("NotchPrompter needs the camera to record you. Turn it on for NotchPrompter in System Settings → Privacy & Security → Camera.", cameraSettings))
                }
            }
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async {
                    done(mic ? nil : ("NotchPrompter needs the microphone to record your voice. Turn it on for NotchPrompter in System Settings → Privacy & Security → Microphone.", VoiceListener.microphoneSettings))
                }
            }
        }
    }

    private var prepared = false
    private var startedCallback: ((String?) -> Void)?

    /// Turn on the camera and microphone without saving anything yet, so a take can start
    /// instantly (the camera needs a second or so to wake up). `ready` gets nil or a problem.
    func prepare(cameraID: String, ready: @escaping (String?) -> Void) {
        guard !isRecording else { return ready(nil) }
        let camera = Self.cameras.first { $0.uniqueID == cameraID } ?? AVCaptureDevice.default(for: .video)
        guard let camera else { return ready("No camera found.") }
        guard let mic = AVCaptureDevice.default(for: .audio) else { return ready("No microphone found.") }

        queue.async { [self] in
            do {
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                session.outputs.forEach(session.removeOutput)
                session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
                for input in [try AVCaptureDeviceInput(device: camera), try AVCaptureDeviceInput(device: mic)] {
                    guard session.canAddInput(input) else { throw RecorderError.setup }
                    session.addInput(input)
                }
                guard session.canAddOutput(output) else { throw RecorderError.setup }
                session.addOutput(output)
                audioOutput.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
                                             AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false,
                                             AVNumberOfChannelsKey: 1, AVSampleRateKey: 16_000]
                audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
                if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
                session.commitConfiguration()
                session.startRunning()
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                DispatchQueue.main.async { self.prepared = true; ready(nil) }
            } catch {
                session.commitConfiguration()
                session.stopRunning()
                log.error("recorder: \(error.localizedDescription)")
                DispatchQueue.main.async { ready("Couldn't start recording: \(error.localizedDescription)") }
            }
        }
    }

    /// Start saving the take (after `prepare`). `started` runs when the first frames are written.
    func record(name: String, started: @escaping (String?) -> Void) {
        guard prepared, !isRecording else { return started(prepared ? nil : "The camera isn't ready.") }
        isRecording = true
        startedAt = Date()
        startedCallback = started
        queue.async { [self] in
            output.startRecording(to: Self.folder.appendingPathComponent(name + ".mov"), recordingDelegate: self)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.startedAt = Date()
            self.startedCallback?(nil)
            self.startedCallback = nil
        }
    }

    /// Stop the take. The file is finished when `onFinished` runs (then `completion`).
    func stop(completion: (() -> Void)? = nil) {
        guard isRecording else {
            // Prepared but never started (cancelled during the countdown): just turn the camera off.
            if prepared { prepared = false; queue.async { self.session.stopRunning() } }
            completion?()
            return
        }
        prepared = false
        stopCompletion = completion
        queue.async { self.output.stopRecording() }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // An error can still mean a good file (e.g. the disk filled up after some seconds).
        let ok = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        queue.async { self.session.stopRunning() }
        DispatchQueue.main.async {
            self.isRecording = false
            self.onFinished(ok ? url : nil, ok ? nil : "The recording couldn't be saved: \(error?.localizedDescription ?? "")")
            self.stopCompletion?()
            self.stopCompletion = nil
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onAudio?(sampleBuffer)
    }

    /// "NotchPrompter 2026-09-23 at 11.28.26", shared by the camera and screen movies of one take.
    static func takeName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "NotchPrompter \(f.string(from: Date()))"
    }

    private enum RecorderError: LocalizedError {
        case setup
        var errorDescription: String? { "The camera or microphone is busy." }
    }
}
