import AppKit
import Combine
import CoreServices
import NotchPrompterKit

/// Keeps the script library as Markdown files in a folder the user picks, both ways, so any
/// editor — or an AI assistant such as Claude Code or Codex — can read and write the scripts.
///
/// Each script is one file: the file name is the title, the file is the text. Editing, adding,
/// renaming or deleting a file does the same to the script, and the other way round.
final class ScriptFolder: ObservableObject {
    static let shared = ScriptFolder(library: .shared)

    /// The folder, while syncing.
    @Published private(set) var url: URL?

    private let library: ScriptLibrary
    private var state = State()
    private var stream: FSEventStreamRef?
    private var syncWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()

    /// Which file each script is, and the text last seen in each file. A file whose text differs
    /// from `synced` was changed outside the app; a script whose text differs was changed in it.
    private struct State: Codable {
        var files: [UUID: String] = [:]
        var synced: [String: String] = [:]
    }

    private static let bookmarkKey = "scriptFolderBookmark"
    private static let stateURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchPrompter/script-folder.json")
    private static let extensions: Set<String> = ["md", "markdown", "txt"]
    /// Notes for assistants and people, not scripts.
    private static let ignored: Set<String> = ["agents.md", "claude.md", "readme.md"]

    init(library: ScriptLibrary) {
        self.library = library
        if let data = try? Data(contentsOf: Self.stateURL), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        }
        #if DEBUG
        // For testing the sync without the folder panel: NOTCHPROMPTER_SCRIPT_FOLDER=/some/folder
        if let path = ProcessInfo.processInfo.environment["NOTCHPROMPTER_SCRIPT_FOLDER"] {
            start(URL(fileURLWithPath: path, isDirectory: true))
            return
        }
        #endif
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            log.error("script folder: can't open the saved folder")
            return
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        start(url)
    }

    // MARK: Choosing the folder

    /// Ask for a folder and start syncing with it.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Use Folder")
        panel.message = String(localized: "Choose an empty folder, or one with only scripts in it. Every Markdown and text file in it becomes a script.")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        stop()
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        _ = url.startAccessingSecurityScopedResource()
        state = State()   // a new folder: match its files to the scripts again
        start(url)
    }

    /// Stop syncing. The files stay where they are.
    func stop() {
        guard let url else { return }
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        subscriptions.removeAll()
        url.stopAccessingSecurityScopedResource()
        self.url = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    /// The folder for Settings, with the home folder as "~".
    var displayPath: String {
        guard let path = url?.path else { return "" }
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    func reveal() {
        if let url { NSWorkspace.shared.open(url) }
    }

    private func start(_ url: URL) {
        self.url = url
        writeNotes(in: url)
        sync()
        watch(url)
        library.$scripts.dropFirst().sink { [weak self] _ in self?.scheduleSync() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.scheduleSync() }.store(in: &subscriptions)
    }

    private func watch(_ url: URL) {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ScriptFolder>.fromOpaque(info).takeUnretainedValue().scheduleSync()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// Library changes come in on every keystroke, and file events in bursts: sync once they settle.
    private func scheduleSync() {
        syncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sync() }
        syncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Syncing

    private struct File {
        var text: String
        var modified: Date
    }

    func syncNow() {
        syncWork?.cancel()
        sync()
    }

    /// Bring the folder and the library together. Doing it twice changes nothing, so the app's own
    /// writes, which also cause file events, come back as no change.
    private func sync() {
        guard let folder = url else { return }
        let fm = FileManager.default
        var files: [String: File] = [:]
        // An unplugged disk or a missing folder must never read as "all files deleted".
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else {
            log.error("script folder: can't read the folder")
            return
        }
        // iCloud Drive can swap a file for a hidden ".Name.md.icloud" placeholder to save space.
        // The file is still there: download it, and leave its script alone until it is back.
        var evicted = Set<String>()
        for name in names where name.hasPrefix(".") && name.hasSuffix(".icloud") {
            let original = String(name.dropFirst().dropLast(".icloud".count))
            evicted.insert(original)
            try? fm.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(original))
        }
        for name in names where !name.hasPrefix(".") && !Self.ignored.contains(name.lowercased())
            && Self.extensions.contains((name as NSString).pathExtension.lowercased()) {
            let fileURL = folder.appendingPathComponent(name)
            // Half written, or not UTF-8: not a deleted file. Try again at the next change.
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { evicted.insert(name); continue }
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            files[name] = File(text: text, modified: modified)
        }

        // Every script file gone at once is much more likely a folder problem than a choice:
        // keep the scripts, and write their files again.
        if files.isEmpty && evicted.isEmpty && state.files.count > 1 {
            log.error("script folder: all script files are missing, writing them again")
            state = State()
        }

        // 1. Mapped files that are gone: renamed (a new file with the same text) or deleted.
        var unmapped = Set(files.keys).subtracting(state.files.values)
        for (id, name) in state.files where files[name] == nil && !evicted.contains(name) {
            if let renamed = unmapped.first(where: { files[$0]?.text == state.synced[name] }) {
                unmapped.remove(renamed)
                state.files[id] = renamed
                state.synced[renamed] = state.synced.removeValue(forKey: name)
                if library.script(id) != nil { library.setTitle(Self.title(of: renamed), of: id) }
            } else {
                state.files[id] = nil
                state.synced[name] = nil
                if library.script(id) != nil { library.delete(id) }
            }
        }

        // 2. Mapped files changed outside the app: the file's text wins.
        for (id, name) in state.files {
            guard let file = files[name], file.text != state.synced[name] else { continue }
            state.synced[name] = file.text
            if library.script(id) != nil {
                library.setText(file.text, of: id)
            } else {
                // Deleted in the app, but edited in the folder since: keep it, as a new script.
                state.files[id] = nil
                unmapped.insert(name)
            }
        }

        // 3. New files: the script with the same title (when linking a folder again), or a new script.
        for name in unmapped.sorted() {
            guard let file = files[name] else { continue }
            let mapped = Set(state.files.keys)
            if let script = library.scripts.first(where: { !mapped.contains($0.id) && Self.fileStem(for: $0) == Self.title(of: name) }) {
                state.files[script.id] = name
                if file.text != script.text && file.modified > script.modified {
                    library.setText(file.text, of: script.id)
                    state.synced[name] = file.text
                } else {
                    state.synced[name] = nil   // written below
                }
            } else {
                let script = library.add(title: Self.title(of: name), text: file.text)
                state.files[script.id] = name
                state.synced[name] = file.text
            }
        }

        // 4. The library to the folder: names follow titles, and changed texts are written.
        let alive = Set(library.scripts.map(\.id))
        var taken = Set(state.files.filter { alive.contains($0.key) }.values.map { $0.lowercased() })
        for script in library.scripts.reversed() {   // oldest first, so the older script keeps the plain name
            let stem = Self.fileStem(for: script)
            var name = state.files[script.id]
            if let current = name, !Self.name(current, fits: stem) {
                taken.remove(current.lowercased())
                let target = Self.freeName(stem, ext: (current as NSString).pathExtension, taken: taken)
                do {
                    try fm.moveItem(at: folder.appendingPathComponent(current), to: folder.appendingPathComponent(target))
                    state.synced[target] = state.synced.removeValue(forKey: current)
                    name = target
                } catch {
                    log.error("script folder: can't rename \(current): \(error.localizedDescription)")
                }
                taken.insert((name ?? current).lowercased())
            } else if name == nil {
                name = Self.freeName(stem, ext: "md", taken: taken)
                taken.insert(name!.lowercased())
            }
            guard let name, !evicted.contains(name) else { continue }
            if state.synced[name] != script.text {
                do {
                    try script.text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
                    state.synced[name] = script.text
                } catch {
                    // Not mapped without a file, or the next sync would read it as deleted.
                    log.error("script folder: can't write \(name): \(error.localizedDescription)")
                    if files[name] == nil { continue }
                }
            }
            state.files[script.id] = name
        }

        // 5. Scripts deleted in the app: their files go to the Trash, so nothing is lost for good.
        for (id, name) in state.files where !alive.contains(id) {
            try? fm.trashItem(at: folder.appendingPathComponent(name), resultingItemURL: nil)
            state.files[id] = nil
            state.synced[name] = nil
        }

        if let data = try? JSONEncoder().encode(state) { try? data.write(to: Self.stateURL, options: .atomic) }
    }

    // MARK: Names

    static func title(of name: String) -> String { (name as NSString).deletingPathExtension }

    /// The title as a file name: no slashes or colons, not hidden, not too long.
    static func fileStem(for script: Script) -> String {
        var stem = script.displayTitle
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines)).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        while stem.hasPrefix(".") { stem.removeFirst() }
        if stem.isEmpty { stem = "Script" }
        return String(stem.prefix(100))
    }

    /// "Intro.md" and "Intro 2.md" both fit the stem "Intro".
    private static func name(_ name: String, fits stem: String) -> Bool {
        let title = title(of: name)
        if title == stem { return true }
        guard title.hasPrefix(stem + " ") else { return false }
        return Int(title.dropFirst(stem.count + 1)) != nil
    }

    private static func freeName(_ stem: String, ext: String, taken: Set<String>) -> String {
        let ext = ext.isEmpty ? "md" : ext
        var name = "\(stem).\(ext)", n = 2
        while taken.contains(name.lowercased()) || ignored.contains(name.lowercased()) {
            name = "\(stem) \(n).\(ext)"
            n += 1
        }
        return name
    }

    /// Script with this title, for `notchprompter://show?script=`: the title or the file name.
    func script(named query: String) -> Script? {
        let q = Self.title(of: query).lowercased()
        return library.scripts.first { $0.displayTitle.lowercased() == q }
            ?? library.scripts.first { state.files[$0.id].map(Self.title(of:))?.lowercased() == q }
    }

    // MARK: Notes for assistants

    /// Tell AI assistants what the folder is. Written once; the user may change them.
    private func writeNotes(in folder: URL) {
        let agents = folder.appendingPathComponent("AGENTS.md")
        if !FileManager.default.fileExists(atPath: agents.path) {
            try? Self.agentNotes.write(to: agents, atomically: true, encoding: .utf8)
        }
        // Claude Code reads CLAUDE.md, which can point to the same notes.
        let claude = folder.appendingPathComponent("CLAUDE.md")
        if !FileManager.default.fileExists(atPath: claude.path) {
            try? "@AGENTS.md\n".write(to: claude, atomically: true, encoding: .utf8)
        }
    }

    private static let agentNotes = """
    # NotchPrompter scripts

    This folder is synced with NotchPrompter, a teleprompter for the Mac that sits under the camera notch.
    NotchPrompter reads and writes the files here while it runs.

    - Each `.md` or `.txt` file is one script. The file name is the title. The file content is the text \
    that is read aloud. `AGENTS.md`, `CLAUDE.md` and `README.md` are not scripts.
    - Changes show in the app within a second. A new file is a new script. Renaming a file renames the \
    script. Deleting a file deletes the script.
    - Write plain spoken text: short sentences and short paragraphs. Markdown formatting is shown as is, \
    so don't use headings, lists or bold.
    - Stage directions go in brackets, like `(pause)` or `[smile]`. They are shown, but not read aloud, \
    and the prompter moves past them.
    - People read at about 150 words a minute. A 60-second script is about 150 words.
    - Recorded takes are in `~/Movies/NotchPrompter`. Each take can have a `.srt` file with the same \
    name: what was actually said, with times. Compare it with the script to find skipped or changed lines.

    To show a script in the prompter, run:

    ```sh
    open "notchprompter://show?script=<title>"
    ```

    Use the file name without `.md`, URL-encoded (for example `Product%20demo`).
    """
}
