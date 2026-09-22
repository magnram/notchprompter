import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings = AppSettings.shared
    private let library = ScriptLibrary.shared
    private var prompter: Prompter!
    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        prompter = Prompter(settings: settings, library: library)
        prompter.onOpenEditor = { [unowned self] in showEditor() }
        buildStatusItem()
        for url in pendingURLs { prompter.importAndShow(url) }
        pendingURLs = []

        #if DEBUG
        if let folder = ScreenshotRenderer.outputFolder {
            // A timer, not the main queue: the renderer spins the run loop and needs queued work to run.
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                MainActor.assumeIsolated { ScreenshotRenderer.run(prompter: self.prompter, folder: folder) }
            }
            return
        }
        #endif
        if settings.hasSeenWelcome {
            prompter.showPanel()
        } else {
            showWelcome()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showEditor() }
        prompter.showPanel()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard prompter?.isRecording == true else { return .terminateNow }
        // Let the movie file finish, or the take is lost.
        prompter.stopRecording { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        prompter.stopAll()
        library.saveNow()
    }

    /// Files opened before launch finished (e.g. by opening a document with the app) wait here.
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let prompter else { pendingURLs += urls; return }
        for url in urls { prompter.importAndShow(url) }
        if settings.hasSeenWelcome { prompter.showPanel() }
    }

    // MARK: Windows

    private func makeWindow<V: View>(_ title: String, _ view: V, style: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = style
        window.isReleasedWhenClosed = false
        return window
    }

    @objc func showEditor() {
        if editorWindow == nil {
            let view = EditorView(library: library, settings: settings,
                                  onRead: { [unowned self] in
                                      editorWindow?.miniaturize(nil)
                                      prompter.startVoice()
                                  },
                                  onPlay: { [unowned self] in
                                      editorWindow?.miniaturize(nil)
                                      prompter.togglePlay()
                                  })
            let window = makeWindow(String(localized: "Scripts", comment: "Title of the script editor window"), view,
                                    style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            window.setContentSize(NSSize(width: 820, height: 540))
            window.setFrameAutosaveName("Editor")
            if !window.setFrameUsingName("Editor") { window.center() }
            window.toolbarStyle = .unified
            editorWindow = window
        }
        NSApp.activate()
        editorWindow?.deminiaturize(nil)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = makeWindow(String(localized: "Settings", comment: "Title of the Settings window"),
                                    SettingsView(settings: settings), style: [.titled, .closable])
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showWelcome() {
        if welcomeWindow == nil {
            let view = OnboardingView { [unowned self] startVoice in
                settings.hasSeenWelcome = true
                welcomeWindow?.close()
                prompter.showPanel()
                if startVoice { prompter.startVoice() }
            }
            let window = makeWindow(String(localized: "Welcome to NotchPrompter"), view, style: [.titled, .closable, .fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.center()
            welcomeWindow = window
        }
        NSApp.activate()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Actions

    @objc private func togglePrompter() { prompter.togglePanel() }
    @objc private func toggleVoice() { prompter.toggleVoice() }
    @objc private func togglePlay() { prompter.togglePlay() }
    @objc private func toggleRecording() { prompter.toggleRecording() }
    @objc private func restart() { prompter.restart() }
    @objc private func biggerText() { prompter.changeFontSize(2) }
    @objc private func smallerText() { prompter.changeFontSize(-2) }
    @objc private func faster() { prompter.changeSpeed(5) }
    @objc private func slower() { prompter.changeSpeed(-5) }

    @objc private func newScript() {
        showEditor()
        NotificationCenter.default.post(name: .newScript, object: nil)
    }

    @objc private func importScript() {
        showEditor()
        NotificationCenter.default.post(name: .importScript, object: nil)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/magnram/notchprompter")!)
    }

    @objc private func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://magnram.github.io/notchprompter/support.html")!)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(togglePrompter):
            item.title = prompter.isVisible ? String(localized: "Hide Prompter") : String(localized: "Show Prompter")
        case #selector(toggleVoice):
            item.title = prompter.listening ? String(localized: "Stop Following Voice") : String(localized: "Follow My Voice")
        case #selector(toggleRecording):
            item.title = prompter.isRecording ? String(localized: "Stop Recording") : String(localized: "Record Video…")
        case #selector(togglePlay):
            item.title = prompter.playing ? String(localized: "Pause") : String(localized: "Play")
        default: break
        }
        return true
    }

    // MARK: Menus

    private func item(_ title: String.LocalizationValue, _ action: Selector, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        item(verbatim: String(localized: title), action, key, modifiers)
    }

    private func item(verbatim title: String, _ action: Selector, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "NotchPrompter")
        let menu = NSMenu()
        menu.addItem(item("Show Prompter", #selector(togglePrompter)))
        menu.addItem(.separator())
        menu.addItem(item("Follow My Voice", #selector(toggleVoice)))
        menu.addItem(item("Play", #selector(togglePlay)))
        menu.addItem(item("Record Video…", #selector(toggleRecording)))
        menu.addItem(item("Back to Top", #selector(restart)))
        menu.addItem(.separator())
        menu.addItem(item("Edit Scripts…", #selector(showEditor)))
        menu.addItem(item(verbatim: StandardMenuTitle.settings, #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit NotchPrompter"), action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
        statusItem.menu = menu
    }

    private func buildMainMenu() {
        let main = NSMenu()
        typealias Std = StandardMenuTitle

        let app = NSMenu()
        app.addItem(NSMenuItem(title: String(localized: "About NotchPrompter"),
                               action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        app.addItem(.separator())
        app.addItem(item(verbatim: Std.settings, #selector(showSettings), ","))
        app.addItem(item("Welcome Guide", #selector(showWelcome)))
        app.addItem(.separator())
        let services = NSMenuItem(title: Std.services, action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: Std.services)
        NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: String(localized: "Hide NotchPrompter"), action: #selector(NSApplication.hide(_:)),
                               keyEquivalent: "h"))
        let others = NSMenuItem(title: String(localized: "Hide Others"),
                                action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(NSMenuItem(title: Std.showAll, action: #selector(NSApplication.unhideAllApplications(_:)),
                               keyEquivalent: ""))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: String(localized: "Quit NotchPrompter"), action: #selector(NSApplication.terminate(_:)),
                               keyEquivalent: "q"))
        add(app, "NotchPrompter", to: main)

        let file = NSMenu()
        file.addItem(item("New Script", #selector(newScript), "n"))
        file.addItem(item("Import…", #selector(importScript), "o"))
        file.addItem(item("Edit Scripts", #selector(showEditor), "e"))
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: Std.closeWindow, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        add(file, Std.file, to: main)

        let edit = NSMenu()
        edit.addItem(NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: Std.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: Std.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: Std.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: Std.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(.separator())
        let find = NSMenuItem(title: String(localized: "Find…"), action: #selector(NSResponder.performTextFinderAction(_:)),
                              keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)
        add(edit, Std.edit, to: main)

        let prompterMenu = NSMenu()
        prompterMenu.addItem(item("Show Prompter", #selector(togglePrompter), "p", [.command, .shift]))
        prompterMenu.addItem(.separator())
        prompterMenu.addItem(item("Follow My Voice", #selector(toggleVoice), "v", [.command, .shift]))
        prompterMenu.addItem(item("Play", #selector(togglePlay), "\r"))
        prompterMenu.addItem(item("Record Video…", #selector(toggleRecording), "r", [.command, .option]))
        prompterMenu.addItem(item("Back to Top", #selector(restart), "r", [.command, .shift]))
        prompterMenu.addItem(.separator())
        prompterMenu.addItem(item("Bigger Text", #selector(biggerText), "+"))
        prompterMenu.addItem(item("Smaller Text", #selector(smallerText), "-"))
        prompterMenu.addItem(item("Faster", #selector(faster), String(UnicodeScalar(NSUpArrowFunctionKey)!)))
        prompterMenu.addItem(item("Slower", #selector(slower), String(UnicodeScalar(NSDownArrowFunctionKey)!)))
        add(prompterMenu, String(localized: "Prompter", comment: "Menu bar menu with the prompter commands"), to: main)

        let window = NSMenu()
        window.addItem(NSMenuItem(title: Std.minimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: String(localized: "Zoom", comment: "Window menu: zoom the window"),
                                  action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        add(window, Std.window, to: main)
        NSApp.windowsMenu = window

        let help = NSMenu()
        help.addItem(item("NotchPrompter Help", #selector(openHelp), "?"))
        help.addItem(item("NotchPrompter on GitHub", #selector(openGitHub)))
        add(help, Std.help, to: main)
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    private func add(_ menu: NSMenu, _ title: String, to main: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        holder.submenu = menu
        main.addItem(holder)
    }
}

/// Titles of the standard menus and menu items, in the words macOS uses. They come from AppKit's
/// own translations when AppKit shows the same language as the app (so a menu never mixes two
/// languages), and from this app's string catalog otherwise.
enum StandardMenuTitle {
    static let file = appKit("File", fallback: String(localized: "File", comment: "Menu bar menu"))
    static let edit = appKit("Edit", table: "InputManager", fallback: String(localized: "Edit", comment: "Menu bar menu"))
    static let window = appKit("Window", fallback: String(localized: "Window", comment: "Menu bar menu"))
    static let help = appKit("Help", fallback: String(localized: "Help", comment: "Menu bar menu"))
    static let services = appKit("Services", table: "Services", fallback: String(localized: "Services"))
    static let settings = appKit("Settings\\U2026", fallback: String(localized: "Settings…"))
    static let showAll = appKit("Show All", table: "Common", fallback: String(localized: "Show All"))
    static let closeWindow = appKit("Close Window", fallback: String(localized: "Close Window"))
    static let cut = appKit("Cut", fallback: String(localized: "Cut"))
    static let copy = appKit("Copy", fallback: String(localized: "Copy"))
    static let paste = appKit("Paste", fallback: String(localized: "Paste"))
    static let selectAll = appKit("Select All", fallback: String(localized: "Select All"))
    static let minimize = appKit("Minimize", fallback: String(localized: "Minimize"))

    private static let appKitBundle = Bundle(for: NSApplication.self)

    /// AppKit and the app agree on the language (AppKit also has languages this app doesn't).
    private static let sameLanguage: Bool = {
        func id(_ localization: String?) -> String? {
            guard let localization else { return nil }
            let max = Locale.Language(identifier: localization).maximalIdentifier
            return max.hasPrefix("no-") ? "nb-" + max.dropFirst(3) : max   // AppKit says "no" for Bokmål
        }
        guard let app = id(Bundle.main.preferredLocalizations.first) else { return false }
        return app == id(appKitBundle.preferredLocalizations.first)
    }()

    private static func appKit(_ key: String, table: String = "MenuCommands", fallback: String) -> String {
        guard sameLanguage else { return fallback }
        let missing = "\u{0}"
        let title = appKitBundle.localizedString(forKey: key, value: missing, table: table)
        return title == missing || title.isEmpty ? fallback : title
    }
}
