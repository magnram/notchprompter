import Foundation
import Speech

/// After a take, writes what was said as subtitles (.srt) next to the movie, so the take can be
/// captioned, or checked and cut by an AI assistant. It reads the saved movie, so the times match
/// the movie exactly, and it only uses speech recognition on this Mac.
final class TakeTranscriber {
    /// Transcribers at work, kept until they finish.
    private static var running: [TakeTranscriber] = []

    private var task: SFSpeechRecognitionTask?
    private var onDone: (() -> Void)?
    /// Recognition of a long file can come back in parts, each starting after a pause. A part
    /// that comes again (updated) replaces the one with the same start.
    private var parts: [[TimedWord]] = []
    private var finished = false

    /// The subtitle file that goes with `movie`.
    static func transcript(for movie: URL) -> URL {
        movie.deletingPathExtension().appendingPathExtension("srt")
    }

    /// Start transcribing `movie` in `locale`. `hints` are words from the script, for names.
    static func transcribe(_ movie: URL, locale: String, hints: [String], done: (() -> Void)? = nil) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            log.notice("transcript: speech recognition isn't allowed")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.supportsOnDeviceRecognition else {
            log.notice("transcript: \(locale) can't be recognised on this Mac")
            return
        }
        let transcriber = TakeTranscriber()
        transcriber.onDone = done
        running.append(transcriber)
        transcriber.start(recognizer, movie: movie, hints: hints,
                          spaced: !["ja", "zh", "th", "lo", "km", "my"].contains(Locale(identifier: locale).language.languageCode?.identifier ?? ""))
    }

    private func start(_ recognizer: SFSpeechRecognizer, movie: URL, hints: [String], spaced: Bool) {
        let request = SFSpeechURLRecognitionRequest(url: movie)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = Array(hints.prefix(100))
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !finished else { return }
                if let result { add(result.bestTranscription.segments) }
                if let error {
                    log.notice("transcript: \((error as NSError).domain) \((error as NSError).code): \(error.localizedDescription)")
                }
                if error != nil || result?.isFinal == true { finish(movie, spaced: spaced) }
            }
        }
    }

    private func add(_ segments: [SFTranscriptionSegment]) {
        let words = segments.map { TimedWord(text: $0.substring, start: $0.timestamp, duration: $0.duration) }
        guard let start = words.first?.start else { return }
        if let i = parts.firstIndex(where: { abs(($0.first?.start ?? -1) - start) < 0.05 }) {
            parts[i] = words
        } else {
            parts.append(words)
        }
    }

    private func finish(_ movie: URL, spaced: Bool) {
        finished = true
        defer {
            Self.running.removeAll { $0 === self }
            onDone?()
        }
        // Parts in order, without words that overlap the part before.
        var words: [TimedWord] = []
        for part in parts.sorted(by: { ($0.first?.start ?? 0) < ($1.first?.start ?? 0) }) {
            words += part.filter { $0.start >= (words.last?.end ?? 0) - 0.05 }
        }
        // Nothing heard, or the take was moved to the Trash while this ran.
        guard !words.isEmpty, FileManager.default.fileExists(atPath: movie.path) else { return }
        let srt = Subtitles.srt(Subtitles.cues(words, spaced: spaced))
        do {
            try srt.write(to: Self.transcript(for: movie), atomically: true, encoding: .utf8)
        } catch {
            log.error("transcript: can't save: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
extension TakeTranscriber {
    /// NOTCHPROMPTER_TRANSCRIBE=/path/movie.mov [NOTCHPROMPTER_LOCALE=en-US]: write its transcript and quit.
    /// Asks for speech recognition access the first time.
    static var selfTestMovie: URL? {
        ProcessInfo.processInfo.environment["NOTCHPROMPTER_TRANSCRIBE"].map { URL(fileURLWithPath: $0) }
    }

    static func runSelfTest(_ movie: URL) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { runSelfTest(movie, allowed: status == .authorized) }
        }
    }

    private static func runSelfTest(_ movie: URL, allowed: Bool) {
        print("transcribe self-test: speech access \(allowed ? "allowed" : "not allowed")")
        guard allowed else { exit(2) }
        let locale = ProcessInfo.processInfo.environment["NOTCHPROMPTER_LOCALE"] ?? "en-US"
        transcribe(movie, locale: locale, hints: []) {
            let srt = try? String(contentsOf: transcript(for: movie), encoding: .utf8)
            print(srt ?? "transcribe self-test: no transcript")
            exit(srt == nil ? 1 : 0)
        }
    }
}
#endif
