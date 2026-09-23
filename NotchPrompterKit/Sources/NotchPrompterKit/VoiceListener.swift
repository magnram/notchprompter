import AVFoundation
import NaturalLanguage
import Speech
import os

let log = Logger(subsystem: "com.magnusramm.NotchPrompter", category: "voice")

/// Streams microphone audio into Apple's speech recogniser and reports the words heard so far.
public final class VoiceListener {
    /// All words heard in the current recognition task (partial results included), with a
    /// number that changes each time a new task starts counting from zero.
    public var onWords: (_ task: Int, _ words: [String]) -> Void = { _, _ in }
    public var onStatus: (String) -> Void = { _ in }
    public var onStopped: () -> Void = {}
    /// Microphone or speech recognition access is missing. The message says which, and where to allow it.
    public var onPermissionProblem: (_ message: String, _ settingsURL: URL) -> Void = { _, _ in }
    /// On-device recognition needs Dictation turned on, and `onDeviceOnly` forbids Apple's servers.
    public var onNeedsDictation: () -> Void = {}
    /// Words from the script, to help the recogniser with names and unusual words.
    public var hints: [String] = []
    public private(set) var running = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var taskNumber = 0
    /// On-device recognition is faster and private, but needs Dictation turned on in the system settings.
    private var onDevice = false
    /// Never send audio to Apple's servers; fail instead when the device can't recognise the language.
    public var onDeviceOnly = true
    private var quickErrors = 0
    private var languageName = ""
    private var locale = ""
    private var configObserver: NSObjectProtocol?
    #if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    #endif
    /// Take audio from `append(_:)` (the recorder's microphone) instead of opening the microphone
    /// again. Two readers of one microphone make macOS reconfigure it, which breaks recognition.
    public var useExternalAudio = false

    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?  // guarded by lock (read on the audio thread)
    private var _level: CGFloat = 0                              // guarded by lock (written on the audio thread)

    public init() {}

    /// Microphone loudness from 0 (silence) to 1 (loud speech).
    public var level: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return running ? _level : 0
    }

    public static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    #if os(macOS)
    public static let speechSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    public static let dictationSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    public static let microphoneSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    #else
    /// The app's own page in the Settings app (`UIApplication.openSettingsURLString`).
    public static let speechSettings = URL(string: "app-settings:")!
    public static let dictationSettings = URL(string: "app-settings:")!
    public static let microphoneSettings = URL(string: "app-settings:")!
    #endif

    /// Ask for speech recognition and microphone access. `done` gets nil or a message for the user.
    public static func requestPermissions(_ done: @escaping (String?) -> Void) {
        requestPermissionsWithSettings { problem in done(problem?.message) }
    }

    private static func requestPermissionsWithSettings(_ done: @escaping ((message: String, url: URL)?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                return DispatchQueue.main.async { done((Messages.speechDenied, speechSettings)) }
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { done(granted ? nil : (Messages.microphoneDenied, microphoneSettings)) }
            }
        }
    }

    /// Changes on every start and stop, so a start that is still waiting for permission is
    /// dropped when `stop` comes first. Otherwise the microphone would turn on after all.
    private var generation = 0

    public func start(locale: String) {
        generation += 1
        let started = generation
        VoiceListener.requestPermissionsWithSettings { problem in
            guard started == self.generation else { return }
            if let problem {
                self.stop()
                self.onStopped()
                self.onPermissionProblem(problem.message, problem.url)
            } else {
                self.begin(locale)
            }
        }
    }

    private func begin(_ locale: String) {
        self.locale = locale
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: locale)), r.isAvailable else {
            let name = Locale.interface.localizedString(forIdentifier: locale) ?? locale
            return fail(Messages.unavailable(name))
        }
        if onDeviceOnly && !r.supportsOnDeviceRecognition {
            let name = Locale.interface.localizedString(forIdentifier: locale) ?? locale
            return fail(Messages.notOnDevice(name))
        }
        recognizer = r
        if !useExternalAudio {
            guard startMicrophone() else { return }
            // Another app or a camera recording can change the input device's format, which stops the
            // engine. Start the microphone again on the new format; the recognition task goes on,
            // since a new one would need a few seconds before it hears again.
            configObserver = configObserver ?? NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                guard let self, self.running, !self.useExternalAudio else { return }
                log.notice("audio configuration changed, restarting the microphone")
                self.engine.stop()
                _ = self.startMicrophone()   // on failure it has stopped listening and said why
            }
        }
        #if os(iOS)
        // A phone call or Siri takes the microphone away; stop, so the button shows it is off.
        interruptionObserver = interruptionObserver ?? NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.running, !self.useExternalAudio,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self.stop()
            self.onStopped()
        }
        #endif
        running = true
        onDevice = r.supportsOnDeviceRecognition
        quickErrors = 0
        languageName = Locale.interface.localizedString(forIdentifier: locale) ?? locale
        log.info("start: locale \(locale), on-device \(self.onDevice)")
        restartTask()
        announce()
    }

    /// Feed the microphone to the recogniser. False (after telling the user) when it can't start.
    private func startMicrophone() -> Bool {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true)
        } catch {
            fail(Messages.microphoneFailed); return false
        }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { fail(Messages.noMicrophone); return false }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = VoiceListener.level(of: buffer)
            self.lock.lock(); let req = self.request; self._level = level; self.lock.unlock()
            req?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { fail(Messages.microphoneFailed); return false }
        return true
    }

    private func announce() {
        onStatus(onDevice ? "🎙 \(languageName)" : Messages.viaApple(languageName))
    }

    /// Start a fresh recognition task, so earlier words are forgotten.
    public func restartTask() {
        guard running, let recognizer else { return }
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = onDevice
        req.taskHint = .dictation
        req.addsPunctuation = false
        req.contextualStrings = hints
        lock.lock(); request = req; lock.unlock()
        taskNumber += 1
        let number = taskNumber
        let started = CACurrentMediaTime()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.running, self.currentRequest === req else { return }
                if let result {
                    self.quickErrors = 0
                    self.onWords(number, result.bestTranscription.segments.map(\.substring))
                }
                if let error {
                    let e = error as NSError
                    log.notice("task \(number) error \(e.domain) \(e.code): \(e.localizedDescription)")
                    // "Siri and Dictation are disabled": the device's own speech models are switched off.
                    if self.onDevice && self.onDeviceOnly && e.domain == "kLSRErrorDomain" && e.code == 201 {
                        self.stop()
                        self.onStopped()
                        self.onNeedsDictation()
                        return
                    }
                    if self.onDevice && self.onDeviceOnly && self.quickErrors >= 2 {
                        return self.fail(Messages.onDeviceBroken)
                    }
                    if self.onDevice && !self.onDeviceOnly {
                        // Usually "Siri and Dictation are disabled": use Apple's servers instead.
                        self.onDevice = false
                        self.announce()
                        self.restartTask()
                        return
                    }
                    // An error right after starting means the recogniser is broken, not just idle.
                    self.quickErrors = CACurrentMediaTime() - started < 1.5 ? self.quickErrors + 1 : 0
                    if self.quickErrors >= 5 {
                        return self.fail(Messages.keepsFailing(e.localizedDescription))
                    }
                    // Tasks end after a long pause or at a time limit; keep listening with a new one
                    // straight away, so no words are lost. Wait a little only when it keeps failing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + (self.quickErrors > 0 ? 0.3 : 0)) {
                        if self.currentRequest === req { self.restartTask() }
                    }
                } else if result?.isFinal == true {
                    log.notice("task \(number) finished, starting a new one")
                    self.restartTask()
                }
            }
        }
    }

    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    public func stop() {
        generation += 1
        guard running else { return }
        running = false
        // Don't touch inputNode in recorder mode: creating it opens the microphone.
        if !useExternalAudio {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
        lock.lock(); request?.endAudio(); request = nil; _level = 0; lock.unlock()
        task?.cancel()
        task = nil
    }

    private func fail(_ message: String) {
        stop()
        onStatus(message)
        onStopped()
    }

    /// Audio from the recorder, when `useExternalAudio` is on.
    public func append(_ buffer: CMSampleBuffer) {
        let level = VoiceListener.level(of: buffer)
        lock.lock(); let req = request; _level = level; lock.unlock()
        req?.appendAudioSampleBuffer(buffer)
    }

    /// Loudness of 32-bit float samples (the format the Mac recorder asks for) or 16-bit integer
    /// samples (what the iPhone's capture microphone delivers).
    public static func level(of buffer: CMSampleBuffer) -> CGFloat {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return 0 }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                          dataPointerOut: &pointer) == noErr, let pointer, length >= 4 else { return 0 }
        let format = CMSampleBufferGetFormatDescription(buffer)
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let isInteger = format.map { $0.mFormatFlags & kAudioFormatFlagIsFloat == 0 && $0.mBitsPerChannel == 16 } ?? false
        let n = length / (isInteger ? 2 : 4)
        let sum = isInteger
            ? pointer.withMemoryRebound(to: Int16.self, capacity: n) { samples in
                (0..<n).reduce(Float(0)) { let s = Float(samples[$1]) / 32768; return $0 + s * s }
            }
            : pointer.withMemoryRebound(to: Float.self, capacity: n) { samples in
                (0..<n).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
            }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return CGFloat(min(1, max(0, (db + 55) / 40)))
    }

    public static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return CGFloat(min(1, max(0, (db + 55) / 40)))   // -55 dB → 0, -15 dB → 1
    }

    /// The speech locale that best fits the language a text is written in.
    public static func detectLocale(for text: String) -> String {
        let supported = SFSpeechRecognizer.supportedLocales()
        let fallback = supported.contains(Locale.current) ? Locale.current.identifier : "en-US"
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(3000)))
        guard let dominant = recognizer.dominantLanguage?.rawValue else { return fallback }
        // "zh-Hans" and "zh-Hant" carry a script: keep the speech locales written in it.
        let language = Locale.Language(identifier: dominant)
        var code = language.languageCode?.identifier ?? dominant
        if code == "no" || code == "nn" { code = "nb" }   // speech recognition has Norwegian Bokmål
        var matches = supported.filter { $0.language.languageCode?.identifier == code }
        if let script = language.script {
            let sameScript = matches.filter { $0.language.maximalIdentifier.contains("-\(script.identifier)-") }
            if !sameScript.isEmpty { matches = sameScript }
        }
        // Prefer the user's region, then the region of the app's language (e.g. Portugal for
        // Portuguese (Portugal)), then the language's main region (Germany for German).
        let appRegion = Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "").region
        let mainRegion = Locale.Language(identifier: Locale.Language(identifier: dominant).maximalIdentifier).region
        let preferred = matches.first { $0.region == Locale.current.region }
            ?? matches.first { appRegion != nil && $0.language.region == appRegion }
            ?? matches.first { mainRegion != nil && $0.language.region == mainRegion } ?? matches.first
        return preferred?.identifier ?? fallback
    }
}

/// What the listener tells the user. The Mac and the iPhone name their settings differently.
private enum Messages {
    #if os(macOS)
    static let speechDenied = String(localized: "NotchPrompter needs Speech Recognition to follow your voice. Turn it on for NotchPrompter in System Settings → Privacy & Security → Speech Recognition.", bundle: .module)
    static let microphoneDenied = String(localized: "NotchPrompter needs the microphone to follow your voice. Turn it on for NotchPrompter in System Settings → Privacy & Security → Microphone.", bundle: .module)
    static func notOnDevice(_ name: String) -> String {
        String(localized: "\(name) can't be recognised on this Mac. Allow Apple's servers in Settings → Privacy, or use Play.",
               bundle: .module, comment: "The placeholder is a language name. “Settings → Privacy” is this app's Settings window.")
    }
    static let onDeviceBroken = String(localized: "On-device speech recognition isn't working. Turn on Dictation in System Settings → Keyboard, or allow Apple's servers in Settings → Privacy.", bundle: .module)
    #else
    static let speechDenied = String(localized: "NotchPrompter needs Speech Recognition to follow your voice. Turn it on in Settings → Apps → NotchPrompter.", bundle: .module)
    static let microphoneDenied = String(localized: "NotchPrompter needs the microphone to follow your voice. Turn it on in Settings → Apps → NotchPrompter.", bundle: .module)
    static func notOnDevice(_ name: String) -> String {
        String(localized: "\(name) can't be recognised on this iPhone. Allow Apple's servers in the app's settings, or use Scroll.",
               bundle: .module, comment: "The placeholder is a language name. “the app's settings” is the gear in NotchPrompter.")
    }
    static let onDeviceBroken = String(localized: "On-device speech recognition isn't working. Turn on Dictation in Settings → General → Keyboard, or allow Apple's servers in the app's settings.", bundle: .module)
    #endif
    static func unavailable(_ name: String) -> String {
        String(localized: "Speech recognition isn't available for \(name) right now.",
               bundle: .module, comment: "The placeholder is a language name")
    }
    static let noMicrophone = String(localized: "No microphone found.", bundle: .module)
    static let microphoneFailed = String(localized: "Couldn't start the microphone.", bundle: .module)
    static func viaApple(_ name: String) -> String {
        String(localized: "🎙 \(name) · via Apple", bundle: .module,
               comment: "Status: listening in a language, recognised by Apple's servers")
    }
    static func keepsFailing(_ error: String) -> String {
        String(localized: "Speech recognition keeps failing: \(error)", bundle: .module,
               comment: "The placeholder is the system's error message")
    }
}

extension Locale {
    /// The language the app is shown in, for naming languages ("German", "Deutsch") in the same one.
    public static var interface: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }
}
