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

/// All the user's scripts, stored as JSON in the app's Application Support folder, and kept the
/// same on the user's Macs and iPhones through iCloud.
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
    private let cloud: KeyValueCloud?
    private let keepsLocal: (Script) -> Bool
    private var cloudObserver: NSObjectProtocol?

    /// `welcome` makes the practice script for a first launch, in the app's language.
    /// `keepsLocal` picks the scripts that stay on this device: the unchanged practice script,
    /// which each app has in its own words. `syncs` is false for demos and screenshots, so they
    /// never reach the user's iCloud.
    public convenience init(welcome: () -> Script, keepsLocal: @escaping (Script) -> Bool = { _ in false },
                            syncs: Bool = true) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchPrompter", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.init(fileURL: support.appendingPathComponent("scripts.json"), welcome: welcome, keepsLocal: keepsLocal,
                  cloud: syncs ? NSUbiquitousKeyValueStore.default : nil)
    }

    init(fileURL: URL, welcome: () -> Script, keepsLocal: @escaping (Script) -> Bool, cloud: KeyValueCloud?) {
        self.fileURL = fileURL
        self.keepsLocal = keepsLocal
        self.cloud = cloud

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

        if let cloud {
            cloudObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud as AnyObject, queue: .main
            ) { [weak self] _ in self?.cloudChanged() }
            cloud.synchronize()
            cloudChanged()
            cloudPush()   // scripts from before sync was turned on
        }
    }

    deinit {
        if let cloudObserver { NotificationCenter.default.removeObserver(cloudObserver) }
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
        if let script = script(id), !keepsLocal(script) { cloudDelete(id) }
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
        writeFile()
        cloudPush()
    }

    private func writeFile() {
        guard let data = try? JSONEncoder().encode(Stored(scripts: scripts, activeID: activeID)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: iCloud
    //
    // Each script is one key in iCloud key-value storage, holding the script as JSON. A deleted
    // script leaves its ID and the time in `deleted`, so other devices delete it too. When two
    // devices change the same script, the later change wins.

    private static let scriptPrefix = "script."
    private static let deletedKey = "deleted"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // the same script always gives the same data
        return encoder
    }()

    private var cloudDeleted: [String: Date] {
        guard let data = cloud?.data(forKey: Self.deletedKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    /// Take in what other devices changed.
    func cloudChanged() {
        guard let cloud else { return }
        let deleted = cloudDeleted
        var changed = false
        for key in cloud.keys where key.hasPrefix(Self.scriptPrefix) {
            guard let data = cloud.data(forKey: key),
                  let remote = try? JSONDecoder().decode(Script.self, from: data) else { continue }
            if let when = deleted[remote.id.uuidString], when >= remote.modified { continue }
            if let i = scripts.firstIndex(where: { $0.id == remote.id }) {
                guard remote.modified > scripts[i].modified else { continue }
                scripts[i] = remote
            } else {
                // Newest first, like scripts made here.
                scripts.insert(remote, at: scripts.firstIndex { $0.modified < remote.modified } ?? scripts.endIndex)
            }
            changed = true
        }
        for (id, when) in deleted {
            guard let uuid = UUID(uuidString: id), let i = scripts.firstIndex(where: { $0.id == uuid }),
                  scripts[i].modified <= when, !keepsLocal(scripts[i]) else { continue }
            scripts.remove(at: i)
            changed = true
        }
        guard changed else { return }
        if scripts.isEmpty { scripts = [Script(title: "", text: "")] }
        if active == nil { activeID = scripts.first?.id }
        writeFile()
    }

    /// Send the scripts that changed here.
    private func cloudPush() {
        guard let cloud else { return }
        for script in scripts where !keepsLocal(script) {
            let key = Self.scriptPrefix + script.id.uuidString
            guard let data = try? Self.encoder.encode(script), cloud.data(forKey: key) != data else { continue }
            cloud.store(data, forKey: key)
        }
    }

    private func cloudDelete(_ id: UUID) {
        guard let cloud else { return }
        var deleted = cloudDeleted
        deleted[id.uuidString] = Date()
        if let data = try? JSONEncoder().encode(deleted) { cloud.store(data, forKey: Self.deletedKey) }
        cloud.store(nil, forKey: Self.scriptPrefix + id.uuidString)
    }
}

/// The part of iCloud key-value storage the library uses. Tests use one in memory.
protocol KeyValueCloud: AnyObject {
    var keys: [String] { get }
    func data(forKey key: String) -> Data?
    /// nil removes the key.
    func store(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueCloud {
    var keys: [String] { Array(dictionaryRepresentation.keys) }
    func store(_ data: Data?, forKey key: String) {
        if let data { set(data, forKey: key) } else { removeObject(forKey: key) }
    }
}
