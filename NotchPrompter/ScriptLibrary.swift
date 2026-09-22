import AppKit
import Combine
import UniformTypeIdentifiers

struct Script: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var modified = Date()

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }

    /// About how long the script takes to read aloud, at 150 words a minute.
    var readingTime: String {
        let seconds = Int((Double(wordCount) / 150 * 60).rounded())
        if seconds < 60 { return "\(max(seconds, wordCount > 0 ? 1 : 0)) sec" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m) min \(s) sec"
    }

    var displayTitle: String { title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title }
}

/// All the user's scripts, stored as JSON in the app's Application Support folder.
final class ScriptLibrary: ObservableObject {
    static let shared = ScriptLibrary()

    @Published private(set) var scripts: [Script] = []
    /// The script shown in the prompter.
    @Published var activeID: UUID? { didSet { scheduleSave() } }

    private struct Stored: Codable {
        var scripts: [Script]
        var activeID: UUID?
    }

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchPrompter", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("scripts.json")

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            scripts = stored.scripts
            activeID = stored.activeID
        }
        if scripts.isEmpty {
            let welcome = Script(title: "Welcome", text: Self.welcomeText)
            scripts = [welcome]
            activeID = welcome.id
        }
        if active == nil { activeID = scripts.first?.id }
    }

    var active: Script? { scripts.first { $0.id == activeID } }

    func script(_ id: UUID) -> Script? { scripts.first { $0.id == id } }

    // MARK: Editing

    @discardableResult
    func add(title: String = "", text: String = "") -> Script {
        let script = Script(title: title, text: text)
        scripts.insert(script, at: 0)
        scheduleSave()
        return script
    }

    func setText(_ text: String, of id: UUID) {
        guard let i = scripts.firstIndex(where: { $0.id == id }), scripts[i].text != text else { return }
        scripts[i].text = text
        scripts[i].modified = Date()
        scheduleSave()
    }

    func setTitle(_ title: String, of id: UUID) {
        guard let i = scripts.firstIndex(where: { $0.id == id }), scripts[i].title != title else { return }
        scripts[i].title = title
        scripts[i].modified = Date()
        scheduleSave()
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Script? {
        guard let original = script(id) else { return nil }
        return add(title: original.displayTitle + " copy", text: original.text)
    }

    func delete(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        if scripts.isEmpty { add(title: "Untitled") }
        if activeID == id { activeID = scripts.first?.id }
        scheduleSave()
    }

    // MARK: Files

    /// File types that can be imported: plain text, Markdown, RTF, Word and HTML.
    static let importTypes: [UTType] = [.plainText, .text, .rtf, .rtfd, .html,
                                        UTType(filenameExtension: "md") ?? .plainText,
                                        UTType(filenameExtension: "docx") ?? .data,
                                        UTType(filenameExtension: "doc") ?? .data,
                                        UTType(filenameExtension: "odt") ?? .data]

    /// Read a document as plain text and add it to the library.
    func importFile(at url: URL) throws -> Script {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        let text: String
        if ["txt", "md", "markdown", "text", ""].contains(ext) {
            text = try String(contentsOf: url, encoding: .utf8)
        } else {
            text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        }
        return add(title: url.deletingPathExtension().lastPathComponent, text: text)
    }

    func export(_ id: UUID, to url: URL) throws {
        guard let script = script(id) else { return }
        try script.text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        guard let data = try? JSONEncoder().encode(Stored(scripts: scripts, activeID: activeID)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static let welcomeText = """
    Welcome to NotchPrompter.

    Press the microphone below and read this out loud. The text follows your voice, so the next words are always right under your camera.

    Keep your eyes up here. To the people watching, it looks like you are talking straight to them.

    If you lose your place, click the word you are on, and the prompter continues from there.

    Notes to yourself go in brackets. (take a breath) You don't read them out loud, and the prompter moves past them.

    Prefer a steady pace? Press play instead. Hover over the text to pause, and use the tortoise and the hare to change the speed.

    To write your own script, click the pencil. Your scripts are saved on this Mac.

    That is all. Have a great recording!
    """
}
