import AVFoundation
import NaturalLanguage
import Speech
import os

let log = Logger(subsystem: "com.magnusramm.NotchPrompter", category: "voice")

/// Streams microphone audio into Apple's speech recogniser and reports the words heard so far.
final class VoiceListener {
    /// All words heard in the current recognition task (partial results included), with a
    /// number that changes each time a new task starts counting from zero.
    var onWords: (_ task: Int, _ words: [String]) -> Void = { _, _ in }
    var onStatus: (String) -> Void = { _ in }
    var onStopped: () -> Void = {}
    /// Microphone or speech recognition access is missing. The message says which, and where to allow it.
    var onPermissionProblem: (_ message: String, _ settingsURL: URL) -> Void = { _, _ in }
    /// On-device recognition needs Dictation turned on, and `onDeviceOnly` forbids Apple's servers.
    var onNeedsDictation: () -> Void = {}
    /// Words from the script, to help the recogniser with names and unusual words.
    var hints: [String] = []
    private(set) var running = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var taskNumber = 0
    /// On-Mac recognition is faster and private, but needs Dictation turned on in System Settings.
    private var onDevice = false
    /// Never send audio to Apple's servers; fail instead when the Mac can't recognise the language.
    var onDeviceOnly = true
    private var quickErrors = 0
    private var languageName = ""
    private var locale = ""
    private var configObserver: NSObjectProtocol?
    /// Take audio from `append(_:)` (the recorder's microphone) instead of opening the microphone
    /// again. Two readers of one microphone make macOS reconfigure it, which breaks recognition.
    var useExternalAudio = false

    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?  // guarded by lock (read on the audio thread)
    private var _level: CGFloat = 0                              // guarded by lock (written on the audio thread)

    /// Microphone loudness from 0 (silence) to 1 (loud speech).
    var level: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return running ? _level : 0
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static let speechSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    static let dictationSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    static let microphoneSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    /// Ask for speech recognition and microphone access. `done` gets nil or a message for the user.
    static func requestPermissions(_ done: @escaping (String?) -> Void) {
        requestPermissionsWithSettings { problem in done(problem?.message) }
    }

    private static func requestPermissionsWithSettings(_ done: @escaping ((message: String, url: URL)?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                return DispatchQueue.main.async {
                    done((String(localized: "NotchPrompter needs Speech Recognition to follow your voice. Turn it on for NotchPrompter in System Settings → Privacy & Security → Speech Recognition."), speechSettings))
                }
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    done(granted ? nil : (String(localized: "NotchPrompter needs the microphone to follow your voice. Turn it on for NotchPrompter in System Settings → Privacy & Security → Microphone."), microphoneSettings))
                }
            }
        }
    }

    func start(locale: String) {
        VoiceListener.requestPermissionsWithSettings { problem in
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
            return fail(String(localized: "Speech recognition isn't available for \(name) right now.",
                               comment: "The placeholder is a language name"))
        }
        if onDeviceOnly && !r.supportsOnDeviceRecognition {
            let name = Locale.interface.localizedString(forIdentifier: locale) ?? locale
            return fail(String(localized: "\(name) can't be recognised on this Mac. Allow Apple's servers in Settings → Privacy, or use Play.",
                               comment: "The placeholder is a language name. “Settings → Privacy” is this app's Settings window."))
        }
        recognizer = r
        if useExternalAudio {
            running = true
        } else {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0 else { return fail(String(localized: "No microphone found.")) }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let level = VoiceListener.level(of: buffer)
                self.lock.lock(); let req = self.request; self._level = level; self.lock.unlock()
                req?.append(buffer)
            }
            engine.prepare()
            do { try engine.start() } catch { return fail(String(localized: "Couldn't start the microphone.")) }
            running = true
            // Another app or a camera recording can change the input device's format, which stops the
            // engine. Start again on the new format.
            configObserver = configObserver ?? NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                guard let self, self.running, !self.useExternalAudio else { return }
                log.info("audio configuration changed, restarting")
                self.stop()
                self.begin(self.locale)
            }
        }
        onDevice = r.supportsOnDeviceRecognition
        quickErrors = 0
        languageName = Locale.interface.localizedString(forIdentifier: locale) ?? locale
        log.info("start: locale \(locale), on-device \(self.onDevice)")
        restartTask()
        announce()
    }

    private func announce() {
        onStatus(onDevice ? "🎙 \(languageName)"
                 : String(localized: "🎙 \(languageName) · via Apple",
                          comment: "Status: listening in a language, recognised by Apple's servers"))
    }

    /// Start a fresh recognition task, so earlier words are forgotten.
    func restartTask() {
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
                    log.info("task \(number) error \(e.domain) \(e.code): \(e.localizedDescription)")
                    // "Siri and Dictation are disabled": the Mac's own speech models are switched off.
                    if self.onDevice && self.onDeviceOnly && e.domain == "kLSRErrorDomain" && e.code == 201 {
                        self.stop()
                        self.onStopped()
                        self.onNeedsDictation()
                        return
                    }
                    if self.onDevice && self.onDeviceOnly && self.quickErrors >= 2 {
                        return self.fail(String(localized: "On-device speech recognition isn't working. Turn on Dictation in System Settings → Keyboard, or allow Apple's servers in Settings → Privacy."))
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
                        return self.fail(String(localized: "Speech recognition keeps failing: \(e.localizedDescription)",
                                                comment: "The placeholder is the system's error message"))
                    }
                    // Tasks end after a long pause or at a time limit; keep listening with a new one.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if self.currentRequest === req { self.restartTask() }
                    }
                } else if result?.isFinal == true {
                    self.restartTask()
                }
            }
        }
    }

    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    func stop() {
        guard running else { return }
        running = false
        // Don't touch inputNode in recorder mode: creating it opens the microphone.
        if !useExternalAudio {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
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
    func append(_ buffer: CMSampleBuffer) {
        let level = VoiceListener.level(of: buffer)
        lock.lock(); let req = request; _level = level; lock.unlock()
        req?.appendAudioSampleBuffer(buffer)
    }

    /// Loudness of 32-bit float samples (the format the recorder delivers).
    static func level(of buffer: CMSampleBuffer) -> CGFloat {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return 0 }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                          dataPointerOut: &pointer) == noErr, let pointer, length >= 4 else { return 0 }
        let n = length / 4
        let sum = pointer.withMemoryRebound(to: Float.self, capacity: n) { samples in
            (0..<n).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
        }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return CGFloat(min(1, max(0, (db + 55) / 40)))
    }

    static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return CGFloat(min(1, max(0, (db + 55) / 40)))   // -55 dB → 0, -15 dB → 1
    }

    /// The speech locale that best fits the language a text is written in.
    static func detectLocale(for text: String) -> String {
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

extension Locale {
    /// The language the app is shown in, for naming languages ("German", "Deutsch") in the same one.
    static var interface: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }
}

/// Finds your place in the script from the words the recogniser heard.
struct VoiceMatcher {
    /// The script's words (normalised for matching) and where they are in the text.
    private(set) var words: [(norm: String, range: NSRange)] = []
    /// Index of the next word to say.
    var cursor = 0
    /// The last heard word (index in the current recognition task) that moved the cursor.
    private var lastUsedSpoken = -1
    private var heardTask = 0

    /// Stage directions like "(pause)" or "[smile]": shown, but not read out loud. Full-width
    /// brackets, as Chinese and Japanese text uses them, count too: "（深呼吸）", "【笑顔】".
    private(set) var cues: [NSRange] = []
    private var length = 0

    private static let cuePattern = try! NSRegularExpression(
        pattern: #"[(（][^()（）\n]*[)）]|[\[［【][^\[\]［］【】\n]*[\]］】]"#)

    mutating func setText(_ text: String) {
        let ns = text as NSString
        length = ns.length
        let cues = Self.cuePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        self.cues = cues
        var found: [(norm: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { w, range, _, _ in
            guard let w, !cues.contains(where: { NSLocationInRange(range.location, $0) }) else { return }
            found.append((VoiceMatcher.normalise(w), range))
        }
        words = found
        cursor = min(cursor, words.count)
    }

    /// Where the said part of the text ends: everything before the next word to say, so the
    /// punctuation and stage directions after the last said word count as said too. An opening
    /// quote or bracket that belongs to the next word does not.
    func saidEnd(in text: NSString) -> Int {
        guard cursor > 0, !words.isEmpty else { return 0 }
        guard cursor < words.count else { return length }
        var end = words[cursor].range.location
        let opening = CharacterSet(charactersIn: "\"'“‘«‹([{¿¡-–—（［【「『")
        func before(_ set: CharacterSet) -> Bool {
            end > 0 && UnicodeScalar(text.character(at: end - 1)).map(set.contains) == true
        }
        while before(opening) { end -= 1 }                          // attached to the next word
        while before(.whitespacesAndNewlines) { end -= 1 }
        return max(end, NSMaxRange(words[cursor - 1].range))
    }

    /// Forget what was heard so far, e.g. after the cursor was moved by hand.
    mutating func resetHeard() { lastUsedSpoken = -1 }

    /// Index of the word at a character position.
    func wordIndex(atCharacter index: Int) -> Int? {
        guard !words.isEmpty else { return nil }
        return words.firstIndex { NSMaxRange($0.range) > index } ?? words.count - 1
    }

    static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Loose word match: exact, a partly heard word, or one letter off in a longer word.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.count >= 3 && b.count >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count] <= 1
    }

    /// Move the cursor to just after the script word that the latest heard words line up with.
    /// Returns true when the cursor moved.
    @discardableResult
    mutating func follow(_ segments: [String], task: Int) -> Bool {
        let heard = segments.flatMap { $0.split(separator: " ") }.map { Self.normalise(String($0)) }
            .filter { !$0.isEmpty }
        // A new recognition task counts heard words from zero again.
        if task != heardTask { heardTask = task; lastUsedSpoken = -1 }
        // The recogniser sometimes revises its guess into fewer words; let the newest one count again.
        if heard.count - 1 < lastUsedSpoken { lastUsedSpoken = heard.count - 2 }
        // Each heard word may move the cursor once; later partial results repeat the same words.
        guard heard.count - 1 > lastUsedSpoken, let last = heard.last, !words.isEmpty else { return false }
        let tail = heard.suffix(5).dropLast()

        let lo = max(0, cursor - 1), hi = min(words.count - 1, cursor + 40)
        guard lo <= hi else { return false }
        var best = -1, bestScore = 0.0
        for p in lo...hi where Self.similar(last, words[p].norm) {
            // Count how many of the words heard just before also line up, allowing a
            // skipped script word or an extra spoken word ("uh").
            var matches = 1, i = p - 1
            for w in tail.reversed() where i >= 0 {
                if Self.similar(w, words[i].norm) { matches += 1; i -= 1 }
                else if i >= 1 && Self.similar(w, words[i - 1].norm) { matches += 1; i -= 2 }
            }
            // Jumping further ahead needs more evidence.
            let distance = p - cursor
            let needed = distance <= 2 ? 1 : distance <= 8 ? 2 : 3
            guard matches >= needed else { continue }
            let score = Double(matches) - Double(abs(distance)) * 0.02
            if score > bestScore { bestScore = score; best = p }
        }
        guard best >= 0, best + 1 > cursor else { return false }
        cursor = best + 1
        lastUsedSpoken = heard.count - 1
        return true
    }
}
