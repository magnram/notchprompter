import SwiftUI
import UniformTypeIdentifiers
import NotchPrompterKit

/// A small editor for the script library: a list of scripts on the left, the text on the right.
struct EditorView: View {
    @ObservedObject var library: ScriptLibrary
    @ObservedObject var settings: AppSettings
    /// Show the prompter and start following the voice with the selected script.
    var onRead: () -> Void
    var onPlay: () -> Void

    @State private var selection: UUID?
    @State private var importing = false
    @State private var exporting = false
    @State private var confirmDelete: UUID?
    @State private var problem: String?
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(library.scripts) { script in
                    ScriptRow(script: script, isActive: script.id == library.activeID)
                        .tag(script.id)
                        .contextMenu {
                            Button("Duplicate") { selection = library.duplicate(script.id)?.id }
                            Button("Export…") { selection = script.id; exporting = true }
                            Divider()
                            Button("Delete…", role: .destructive) { confirmDelete = script.id }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
            .toolbar {
                ToolbarItem {
                    Button { newScript() } label: { Label("New Script", systemImage: "square.and.pencil") }
                        .help("New script (⌘N)")
                }
            }
            .onDeleteCommand { if let selection { confirmDelete = selection } }
        } detail: {
            if let id = selection, let script = library.script(id) {
                ScriptEditor(library: library, script: script, textFocused: $textFocused)
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Script Selected", systemImage: "doc.text")
                } actions: {
                    Button("New Script") { newScript() }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import a text, Markdown, Word or RTF file")
                Button { read(play: true) } label: { Label("Play", systemImage: "play.fill") }
                    .help("Scroll this script at a steady speed")
                    .disabled(selection == nil)
                Button { read(play: false) } label: {
                    Label("Read with Voice", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Show this script under the camera and follow your voice")
                .disabled(selection == nil)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { selection = selection ?? library.activeID ?? library.scripts.first?.id }
        .onReceive(NotificationCenter.default.publisher(for: .newScript)) { _ in newScript() }
        .onReceive(NotificationCenter.default.publisher(for: .importScript)) { _ in importing = true }
        .onChange(of: library.scripts.map(\.id)) { _, ids in
            if let s = selection, !ids.contains(s) { selection = library.activeID ?? ids.first }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ScriptLibrary.importTypes,
                      allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() { selection = try library.importFile(at: url).id }
            } catch {
                problem = String(localized: "That file couldn't be read. Try saving it as plain text or Word first.")
            }
        }
        .fileExporter(isPresented: $exporting, document: PlainTextDocument(text: selectedScript?.text ?? ""),
                      contentType: .plainText, defaultFilename: selectedScript?.displayTitle
                          ?? String(localized: "Script", comment: "Default file name when exporting a script")) { result in
            if case .failure = result { problem = String(localized: "The script couldn't be saved there.") }
        }
        .confirmationDialog("Delete “\(confirmDelete.flatMap(library.script)?.displayTitle ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = confirmDelete { library.delete(id) }
                confirmDelete = nil
            }
        } message: {
            Text("You can't undo this.")
        }
        .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {}
    }

    private var selectedScript: Script? { selection.flatMap(library.script) }

    private func newScript() {
        selection = library.add().id
        DispatchQueue.main.async { textFocused = true }
    }

    private func read(play: Bool) {
        guard let selection else { return }
        library.activeID = selection
        play ? onPlay() : onRead()
    }
}

private struct ScriptRow: View {
    let script: Script
    let isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.displayTitle).font(.headline).lineLimit(1)
                Text(script.text.isEmpty ? String(localized: "Empty", comment: "Preview of a script without text")
                                          : script.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if isActive {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .foregroundStyle(.tint)
                    .help("Shown in the prompter")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ScriptEditor: View {
    @ObservedObject var library: ScriptLibrary
    let script: Script
    var textFocused: FocusState<Bool>.Binding
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title, prompt: Text("Untitled"))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .onChange(of: title) { _, new in library.setTitle(new, of: script.id) }
            Divider().padding(.horizontal, 16)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .focused(textFocused)
                    .onChange(of: text) { _, new in library.setText(new, of: script.id) }
                if text.isEmpty {
                    Text("Write or paste what you want to say.\nBlank lines become new paragraphs in the prompter.")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            Divider()
            HStack {
                HStack(spacing: 5) {
                    Text("\(script.wordCount) words", comment: "Word count below the script editor")
                    Text(verbatim: "·")
                    Text("about \(script.readingTime) to read",
                         comment: "Below the script editor; the time is formatted by the system, e.g. “1 min, 20 sec”")
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                Text("Saved automatically").lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .navigationTitle(script.displayTitle)
        .onAppear {
            title = script.title
            text = script.text
        }
    }
}

struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension Notification.Name {
    static let newScript = Notification.Name("NotchPrompter.newScript")
    static let importScript = Notification.Name("NotchPrompter.importScript")
}
