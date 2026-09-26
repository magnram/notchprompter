import Foundation

/// A recognised word and where it is in the movie, in seconds.
struct TimedWord: Equatable {
    var text: String
    var start: Double
    var duration: Double
    var end: Double { start + duration }
}

/// Turns timed words into SubRip (.srt) subtitles: short cues of one or two lines, split at pauses.
enum Subtitles {
    struct Cue: Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    static let maxLine = 42
    static let maxDuration = 6.0
    static let pause = 0.7

    /// `spaced` is false for languages written without spaces, like Japanese and Chinese.
    static func cues(_ words: [TimedWord], spaced: Bool = true) -> [Cue] {
        let join = spaced ? " " : ""
        var cues: [Cue] = []
        var current: [TimedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            cues.append(Cue(start: first.start, end: last.end, text: lines(current.map(\.text), join: join)))
            current = []
        }

        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let first = current.first, let last = current.last {
                let length = current.map(\.text.count).reduce(0, +) + current.count * join.count + word.text.count
                if word.start - last.end > pause || word.end - first.start > maxDuration || length > 2 * maxLine {
                    flush()
                }
            }
            current.append(word)
        }
        flush()

        // Keep each cue on screen long enough to read, without running into the next one.
        for i in cues.indices {
            let next = i + 1 < cues.count ? cues[i + 1].start : .infinity
            cues[i].end = min(max(cues[i].end, cues[i].start + 1), next)
        }
        return cues
    }

    /// One line, or two when it is long, broken at the word nearest the middle.
    static func lines(_ words: [String], join: String) -> String {
        let text = words.joined(separator: join)
        guard text.count > maxLine, words.count > 1 else { return text }
        var best = 1, bestDiff = Int.max
        for split in 1..<words.count {
            let left = words[..<split].joined(separator: join).count
            let diff = abs(left - (text.count - left - join.count))
            if diff < bestDiff { best = split; bestDiff = diff }
        }
        return words[..<best].joined(separator: join) + "\n" + words[best...].joined(separator: join)
    }

    static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { i, cue in
            "\(i + 1)\n\(time(cue.start)) --> \(time(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// 00:01:02,345
    static func time(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
