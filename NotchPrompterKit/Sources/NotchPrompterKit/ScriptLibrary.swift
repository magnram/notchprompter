import Combine
import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

public struct Script: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var text: String
    public var modified = Date()

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    /// Counts words the way the language does, so Japanese and Chinese, with no spaces, count right too.
    public var wordCount: Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// About how long the script takes to read aloud, at 150 words a minute, e.g. "1 min, 20 sec".
    public var readingTime: String {
        let seconds = Int((Double(wordCount) / 150 * 60).rounded())
        let shown = seconds < 60 ? max(seconds, wordCount > 0 ? 1 : 0) : seconds
        return Duration.seconds(shown).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "Untitled", bundle: .module, comment: "Name of a script without a title") : title
    }
}

/// All the user's scripts, stored as JSON in the app's Application Support folder.
public final class ScriptLibrary: ObservableObject {
    @Published public private(set) var scripts: [Script] = []
    /// The script shown in the prompter.
    @Published public var activeID: UUID? { didSet { scheduleSave() } }

    private struct Stored: Codable {
        var scripts: [Script]
        var activeID: UUID?
    }

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    /// `welcome` makes the practice script for a first launch, in the app's language.
    public init(welcome: () -> Script) {
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
            // First launch: the practice script. Saved scripts are never changed.
            let first = welcome()
            scripts = [first]
            activeID = first.id
        }
        if active == nil { activeID = scripts.first?.id }
    }

    public var active: Script? { scripts.first { $0.id == activeID } }

    public func script(_ id: UUID) -> Script? { scripts.first { $0.id == id } }

    // MARK: Editing

    @discardableResult
    public func add(title: String = "", text: String = "") -> Script {
        let script = Script(title: title, text: text)
        scripts.insert(script, at: 0)
        scheduleSave()
        return script
    }

    public func setText(_ text: String, of id: UUID) {
        guard let i = scripts.firstIndex(where: { $0.id == id }), scripts[i].text != text else { return }
        scripts[i].text = text
        scripts[i].modified = Date()
        scheduleSave()
    }

    public func setTitle(_ title: String, of id: UUID) {
        guard let i = scripts.firstIndex(where: { $0.id == id }), scripts[i].title != title else { return }
        scripts[i].title = title
        scripts[i].modified = Date()
        scheduleSave()
    }

    @discardableResult
    public func duplicate(_ id: UUID) -> Script? {
        guard let original = script(id) else { return nil }
        return add(title: String(localized: "\(original.displayTitle) copy", bundle: .module,
                                 comment: "Title of a duplicated script"),
                   text: original.text)
    }

    public func delete(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        if scripts.isEmpty { add() }
        if activeID == id { activeID = scripts.first?.id }
        scheduleSave()
    }

    // MARK: Files

    #if os(macOS)
    /// File types that can be imported: plain text, Markdown, RTF, Word and HTML.
    public static let importTypes: [UTType] = [.plainText, .text, .rtf, .rtfd, .html,
                                               UTType(filenameExtension: "md") ?? .plainText,
                                               UTType(filenameExtension: "docx") ?? .data,
                                               UTType(filenameExtension: "doc") ?? .data,
                                               UTType(filenameExtension: "odt") ?? .data]
    #else
    /// File types that can be imported: plain text, Markdown, RTF and HTML. iOS can't read Word files.
    public static let importTypes: [UTType] = [.plainText, .text, .rtf, .rtfd, .html,
                                               UTType(filenameExtension: "md") ?? .plainText]
    #endif

    /// Read a document as plain text and add it to the library.
    public func importFile(at url: URL) throws -> Script {
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

    public func export(_ id: UUID, to url: URL) throws {
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

    public func saveNow() {
        saveWork?.cancel()
        guard let data = try? JSONEncoder().encode(Stored(scripts: scripts, activeID: activeID)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
