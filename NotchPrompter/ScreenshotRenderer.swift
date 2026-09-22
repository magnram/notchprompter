#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `NotchPrompter -renderScreens <folder>` captures the app's real windows and puts
/// them on a desktop, for checking the layout and for the App Store screenshots (2880 × 1800).
/// Build without the sandbox to write outside the container (see Tools/render-screens.sh).
enum ScreenshotRenderer {
    static var outputFolder: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderScreens"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    // MARK: Capturing windows

    /// Ask the window server for a window's pixels, so materials and lists look like they do on screen.
    /// CGWindowListCreateImage is hidden from Swift on macOS 15, so look it up at run time.
    private static func capture(_ window: NSWindow) -> NSImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        // listOption .optionIncludingWindow = 8; imageOption .boundsIgnoreFraming = 1 | .bestResolution = 8
        guard let cg = fn(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue(), cg.width > 4
        else { return nil }
        return NSImage(cgImage: cg, size: window.frame.size)
    }

    static func shoot(_ window: NSWindow, wait: TimeInterval = 0.6) -> NSImage {
        let old = window.frame.origin
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.makeFirstResponder(nil)   // no focused field or selected text in the picture
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        let image = capture(window) ?? NSImage(size: window.frame.size)
        window.orderOut(nil)
        window.setFrameOrigin(old)
        return image
    }

    static func window<V: View>(_ title: String, _ view: V, size: NSSize, titled: Bool = true,
                                dark: Bool = false) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = title
        w.styleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        w.toolbarStyle = .unified
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.setContentSize(size)
        return w
    }

    static func write(_ image: NSImage, _ name: String, to folder: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appendingPathComponent(name + ".png"))
    }

    @MainActor
    static func renderStoreShot<V: View>(_ view: V, _ name: String, to folder: URL) {
        let renderer = ImageRenderer(content: view.frame(width: 1440, height: 900))
        renderer.scale = 2
        if let image = renderer.nsImage { write(image, name, to: folder) }
    }

    // MARK: Screens

    static let demoTitle = "Product launch"
    static let demoText = """
    Hi everyone, and thanks for joining.

    Today I want to show you something we have been working on for a long time. It is small, but it changes how you show up on camera.

    You know the feeling. You read your notes, and your eyes drift down and away from the people you are talking to. With NotchPrompter, your script sits right under the camera, so you can keep eye contact the whole time.

    It follows your voice as you speak. Take a pause, go off script, and it simply waits for you to come back.
    """

    @MainActor
    static func run(prompter: Prompter, folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = AppSettings.shared, library = ScriptLibrary.shared
        settings.width = 620
        settings.height = 200
        settings.fontSize = 22
        settings.speed = 40
        for script in library.scripts where script.text != ScriptLibrary.welcomeText { library.delete(script.id) }
        library.add(title: "Weekly team update", text: "Good morning! Three things this week: the new onboarding, the pricing test, and our plans for the conference.")
        library.add(title: "YouTube intro", text: "Hey, welcome back to the channel. Today we are building a tiny Mac app from scratch.")
        let demo = library.add(title: demoTitle, text: demoText)
        library.activeID = demo.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        prompter.panel.sharingType = .readOnly   // the window server hides it from capture otherwise
        prompter.showPanel()

        // The single windows, for checking the layout.
        // Like the real window: as tall as the onboarding needs, which varies with the language.
        let welcomeWindow = window("Welcome", OnboardingView { _ in }, size: NSSize(width: 560, height: 420))
        if let fitting = welcomeWindow.contentViewController?.view.fittingSize { welcomeWindow.setContentSize(fitting) }
        let welcome = shoot(welcomeWindow)
        write(welcome, "window-welcome", to: folder)
        let editorWindow = window("Scripts", EditorView(library: library, settings: settings, onRead: {}, onPlay: {}),
                                  size: NSSize(width: 860, height: 520))
        let editor = shoot(editorWindow, wait: 1)
        write(editor, "window-editor", to: folder)
        let settingsShot = shoot(window("Settings", SettingsView(settings: settings), size: NSSize(width: 460, height: 440)))
        write(settingsShot, "window-settings", to: folder)
        let popover = shoot(window("", SettingsView(settings: settings, compact: true), size: NSSize(width: 340, height: 300),
                                   titled: false, dark: true))
        write(popover, "window-popover", to: folder)

        prompter.debugStage(.reading(word: 40))
        let reading = shoot(prompter.panel, wait: 1)
        write(reading, "prompter-reading", to: folder)
        prompter.debugStage(.playing, hud: String(localized: "▶ Speed \(40)"))
        let playing = shoot(prompter.panel, wait: 1)
        write(playing, "prompter-playing", to: folder)
        prompter.debugStage(.idle)
        let idle = shoot(prompter.panel, wait: 1)
        write(idle, "prompter-idle", to: folder)
        // A big prompter for the close-up, captured at full resolution instead of scaled up.
        settings.width = 1000
        settings.height = 330
        settings.fontSize = 36
        prompter.debugStage(.reading(word: 40))
        let big = shoot(prompter.panel, wait: 1)
        write(big, "prompter-big", to: folder)
        prompter.hidePanel()

        // App Store screenshots.
        renderStoreShot(StoreShot(headline: "Keep eye contact while you read",
                                  detail: "Your script sits right under the camera.",
                                  prompter: reading, wallpaper: 0) { CallWindow() },
                        "appstore-1-eye-contact", to: folder)
        renderStoreShot(StoreShot(headline: "It follows your voice",
                                  detail: "Talk at your own pace. Pause, and it waits for you.",
                                  prompter: big, wallpaper: 1) { EmptyView() },
                        "appstore-2-voice", to: folder)
        renderStoreShot(StoreShot(headline: "Write your scripts right here",
                                  detail: "A simple editor. Import Word, Markdown or text files.",
                                  prompter: idle, wallpaper: 2) {
                            Image(nsImage: editor).resizable().scaledToFit().frame(height: 480).shadowed()
                        },
                        "appstore-3-editor", to: folder)
        renderStoreShot(StoreShot(headline: "Or press play",
                                  detail: "Steady scrolling. Hover to pause. Tortoise and hare for speed.",
                                  prompter: playing, wallpaper: 3) {
                            Image(nsImage: popover).clipShape(RoundedRectangle(cornerRadius: 12)).shadowed()
                        },
                        "appstore-4-play", to: folder)
        renderStoreShot(StoreShot(headline: "Invisible to your audience",
                                  detail: "Hidden from screen sharing and recordings. Nothing leaves your Mac but speech for Apple’s recogniser.",
                                  prompter: reading, wallpaper: 4) {
                            Image(nsImage: settingsShot).resizable().scaledToFit().frame(height: 440).shadowed()
                        },
                        "appstore-5-private", to: folder)
        NSApp.terminate(nil)
    }
}

private extension View {
    func shadowed() -> some View { shadow(color: .black.opacity(0.35), radius: 30, y: 14) }
}

/// A MacBook desktop: wallpaper, menu bar with the notch, and the prompter hanging from the notch.
private struct StoreShot<Content: View>: View {
    let headline: String
    let detail: String
    let prompter: NSImage
    let wallpaper: Int
    @ViewBuilder var content: () -> Content

    private static var palettes: [[Color]] { [
        [Color(red: 0.99, green: 0.55, blue: 0.38), Color(red: 0.62, green: 0.25, blue: 0.85), Color(red: 0.16, green: 0.30, blue: 0.86)],
        [Color(red: 0.07, green: 0.09, blue: 0.20), Color(red: 0.35, green: 0.16, blue: 0.55), Color(red: 0.95, green: 0.35, blue: 0.40)],
        [Color(red: 0.55, green: 0.80, blue: 0.98), Color(red: 0.40, green: 0.48, blue: 0.95), Color(red: 0.70, green: 0.45, blue: 0.95)],
        [Color(red: 0.10, green: 0.45, blue: 0.45), Color(red: 0.15, green: 0.30, blue: 0.55), Color(red: 0.05, green: 0.10, blue: 0.25)],
        [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.30, green: 0.22, blue: 0.40), Color(red: 0.95, green: 0.45, blue: 0.35)],
    ] }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: Self.palettes[wallpaper % Self.palettes.count],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft light blobs so the wallpaper feels like macOS.
            Circle().fill(.white.opacity(0.12)).frame(width: 900).blur(radius: 120).offset(x: -420, y: 420)
            Circle().fill(.white.opacity(0.10)).frame(width: 700).blur(radius: 110).offset(x: 520, y: 80)

            VStack(spacing: 0) {
                MenuBar()
                Spacer()
            }

            // The captured prompter, hanging from the top edge (it covers the notch).
            let scale: CGFloat = 1
            Image(nsImage: prompter)
                .resizable()
                .frame(width: prompter.size.width * scale, height: prompter.size.height * scale)

            VStack(spacing: 10) {
                Spacer().frame(height: prompter.size.height * scale + 40)
                Text(headline)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Spacer().frame(height: 30)
                content()
                Spacer(minLength: 0)
            }
            .shadow(color: .black.opacity(0.2), radius: 8)
        }
        .frame(width: 1440, height: 900)
        .clipped()
    }
}

private struct MenuBar: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.18))
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
                Text(verbatim: "NotchPrompter").fontWeight(.bold)
                ForEach(["File", "Edit", "Prompter", "Window", "Help"], id: \.self) { Text(verbatim: $0) }
                Spacer()
                Image(systemName: "text.aligncenter")
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(verbatim: "Tue 9:41")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
        }
        .frame(height: 34)
    }
}

/// A video call window, for the eye-contact screenshot.
private struct CallWindow: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [[Color.orange, .pink], [.teal, .blue], [.indigo, .purple]][i],
                                         startPoint: .top, endPoint: .bottom).opacity(0.85))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 90))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(verbatim: ["Sara", "Jonas", "Priya"][i])
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(12)
                    }
                    .frame(width: 300, height: 220)
            }
        }
        .padding(18)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18))
        .shadowed()
    }
}
#endif
