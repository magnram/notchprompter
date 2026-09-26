#if DEBUG
import AppKit
import SwiftUI
import NotchPrompterKit

/// Debug builds only: `NotchPrompter -renderScreens <folder>` captures the app's real windows and puts
/// them on a desktop, for checking the layout and for the App Store screenshots (2880 × 1800).
/// Build without the sandbox to write outside the container (see Tools/render-screens.sh and
/// Tools/render-all-languages.sh). The texts in the pictures are in ScreenshotContent.swift.
enum ScreenshotRenderer {
    static var outputFolder: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-renderScreens"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-demoCamera <image>`: the picture in the camera preview, so the camera stays off.
    static let cameraStill = argument("-demoCamera").flatMap(NSImage.init(contentsOfFile:))
    /// `-demoPhone <image>`: the iPhone app's editor, captured in the simulator, for the sync shot.
    static let phoneShot = argument("-demoPhone").flatMap(NSImage.init(contentsOfFile:))

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
        // Controls as in the front window (blue switches), though the window is never really key.
        let w = NSWindow(contentViewController: NSHostingController(rootView: view.environment(\.controlActiveState, .key)))
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
        guard let cg = renderer.cgImage else { return }
        // Opaque and 8 bits per channel: the same picture as with alpha (the desktop fills it), at a
        // fraction of the file size, which matters with 20 languages. The renderer draws in extended
        // sRGB, which an 8-bit context can't hold; Display P3 keeps the colours outside sRGB.
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let flat = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appendingPathComponent(name + ".png"))
    }

    // MARK: Screens

    /// The demo scripts and the texts on the screenshots, in the app's language.
    static let content = ScreenshotContent.current

    @MainActor
    static func run(prompter: Prompter, folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = AppSettings.shared, library = ScriptLibrary.shared
        settings.width = 620
        settings.height = 200
        settings.fontSize = 22
        settings.speed = 40
        // Only the practice script in this language, then the demo scripts.
        if !library.scripts.contains(where: { $0.text == ScriptLibrary.welcomeText }) {
            library.add(title: ScriptLibrary.welcomeTitle, text: ScriptLibrary.welcomeText)
        }
        for script in library.scripts where script.text != ScriptLibrary.welcomeText { library.delete(script.id) }
        library.add(title: content.weeklyTitle, text: content.weeklyText)
        library.add(title: content.youtubeTitle, text: content.youtubeText)
        let demo = library.add(title: content.demoTitle, text: content.demoText)
        library.activeID = demo.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        prompter.panel.sharingType = .readOnly   // the window server hides it from capture otherwise
        prompter.showPanel()

        // The single windows, for checking the layout.
        // Like the real window: as tall as the onboarding needs, which varies with the language.
        let welcomeWindow = window(ScriptLibrary.welcomeTitle, OnboardingView { _ in }, size: NSSize(width: 560, height: 420))
        if let fitting = welcomeWindow.contentViewController?.view.fittingSize { welcomeWindow.setContentSize(fitting) }
        let welcome = shoot(welcomeWindow)
        write(welcome, "window-welcome", to: folder)
        let editorWindow = window(String(localized: "Scripts", comment: "Title of the script editor window"), EditorView(library: library, settings: settings, onRead: {}, onPlay: {}),
                                  size: NSSize(width: 860, height: 520))
        let editor = shoot(editorWindow, wait: 1)
        write(editor, "window-editor", to: folder)
        let settingsWindow = window(String(localized: "Settings", comment: "Title of the Settings window"), SettingsView(settings: settings), size: NSSize(width: 460, height: 440))
        if let fitting = settingsWindow.contentViewController?.view.fittingSize { settingsWindow.setContentSize(fitting) }
        let settingsShot = shoot(settingsWindow)
        write(settingsShot, "window-settings", to: folder)
        let popover = shoot(window("", SettingsView(settings: settings, compact: true), size: NSSize(width: 340, height: 300),
                                   titled: false, dark: true))
        write(popover, "window-popover", to: folder)
        // The menu beside the record button, set up for filming yourself in the screen's light.
        settings.recordingMode = .camera
        settings.screenLight = .light
        settings.saveTranscripts = true
        let recordWindow = window("", RecordShotForm(settings: settings), size: NSSize(width: 380, height: 420),
                                  titled: false, dark: true)
        if let fitting = recordWindow.contentViewController?.view.fittingSize { recordWindow.setContentSize(fitting) }
        let record = shoot(recordWindow)
        write(record, "window-record", to: folder)

        prompter.debugStage(.reading(word: content.readingWord))
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
        prompter.debugStage(.reading(word: content.readingWord))
        let big = shoot(prompter.panel, wait: 1)
        write(big, "prompter-big", to: folder)
        prompter.hidePanel()

        // App Store screenshots. The texts are in `shots` in the order they were added:
        // eye contact, voice, editor, play, private, sync, record.
        let shots = content.shots, phoneShot = Self.phoneShot
        renderStoreShot(StoreShot(headline: shots[0].headline,
                                  detail: shots[0].detail,
                                  prompter: reading, wallpaper: 0) { CallWindow() },
                        "appstore-1-eye-contact", to: folder)
        renderStoreShot(StoreShot(headline: shots[1].headline,
                                  detail: shots[1].detail,
                                  prompter: big, wallpaper: 1) { EmptyView() },
                        "appstore-2-voice", to: folder)
        renderStoreShot(StoreShot(headline: shots[5].headline,
                                  detail: shots[5].detail,
                                  prompter: idle, wallpaper: 5) {
                            HStack(alignment: .bottom, spacing: -70) {
                                Image(nsImage: editor).resizable().scaledToFit().frame(height: 340).shadowed()
                                if let phoneShot { PhoneFrame(screen: phoneShot).frame(height: 400).offset(y: 20).shadowed() }
                            }
                        },
                        "appstore-3-sync", to: folder)
        renderStoreShot(StoreShot(headline: shots[2].headline,
                                  detail: shots[2].detail,
                                  prompter: idle, wallpaper: 2) {
                            Image(nsImage: editor).resizable().scaledToFit().frame(height: 480).shadowed()
                        },
                        "appstore-4-editor", to: folder)
        renderStoreShot(StoreShot(headline: shots[6].headline,
                                  detail: shots[6].detail,
                                  prompter: reading, wallpaper: 0, light: true) {
                            Image(nsImage: record).resizable().scaledToFit().frame(maxHeight: 470)
                                .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.25), radius: 30, y: 14)
                        },
                        "appstore-5-record", to: folder)
        renderStoreShot(StoreShot(headline: shots[3].headline,
                                  detail: shots[3].detail,
                                  prompter: playing, wallpaper: 3) {
                            Image(nsImage: popover).clipShape(RoundedRectangle(cornerRadius: 12)).shadowed()
                        },
                        "appstore-6-play", to: folder)
        renderStoreShot(StoreShot(headline: shots[4].headline,
                                  detail: shots[4].detail,
                                  prompter: reading, wallpaper: 4) {
                            // The lower half of the window, with the shortcuts and privacy, at a readable size.
                            Image(nsImage: settingsShot)
                                .frame(width: settingsShot.size.width, height: 460, alignment: .bottom)
                                .clipped()
                                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)],
                                                     startPoint: .top, endPoint: .bottom))
                                .shadowed()
                        },
                        "appstore-7-private", to: folder)
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
    /// The whole screen as a soft light, as while filming with the screen light on.
    var light = false
    @ViewBuilder var content: () -> Content

    private static var palettes: [[Color]] { [
        [Color(red: 0.99, green: 0.55, blue: 0.38), Color(red: 0.62, green: 0.25, blue: 0.85), Color(red: 0.16, green: 0.30, blue: 0.86)],
        [Color(red: 0.07, green: 0.09, blue: 0.20), Color(red: 0.35, green: 0.16, blue: 0.55), Color(red: 0.95, green: 0.35, blue: 0.40)],
        [Color(red: 0.55, green: 0.80, blue: 0.98), Color(red: 0.40, green: 0.48, blue: 0.95), Color(red: 0.70, green: 0.45, blue: 0.95)],
        [Color(red: 0.10, green: 0.45, blue: 0.45), Color(red: 0.15, green: 0.30, blue: 0.55), Color(red: 0.05, green: 0.10, blue: 0.25)],
        [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.30, green: 0.22, blue: 0.40), Color(red: 0.95, green: 0.45, blue: 0.35)],
        [Color(red: 0.12, green: 0.20, blue: 0.40), Color(red: 0.20, green: 0.55, blue: 0.75), Color(red: 0.45, green: 0.85, blue: 0.75)],
    ] }
    /// Warm white, like the app's soft light.
    private static var lightColors: [Color] { [Color(red: 1, green: 0.97, blue: 0.92), Color(red: 1, green: 0.93, blue: 0.84)] }

    private var ink: Color { light ? Color(white: 0.12) : .white }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: light ? Self.lightColors : Self.palettes[wallpaper % Self.palettes.count],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft light blobs so the wallpaper feels like macOS.
            Circle().fill(.white.opacity(0.12)).frame(width: 900).blur(radius: 120).offset(x: -420, y: 420)
            Circle().fill(.white.opacity(0.10)).frame(width: 700).blur(radius: 110).offset(x: 520, y: 80)

            VStack(spacing: 0) {
                MenuBar(ink: ink)
                Spacer()
            }

            // The captured prompter, hanging from the top edge (it covers the notch).
            let scale: CGFloat = 1
            Image(nsImage: prompter)
                .resizable()
                .frame(width: prompter.size.width * scale, height: prompter.size.height * scale)

            VStack(spacing: 10) {
                Spacer().frame(height: prompter.size.height * scale + 40)
                // Long headlines (German, Finnish, Russian ...) may take two lines, and shrink if needed.
                Text(headline)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: 1300)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ink.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 30)
                content()
                Spacer(minLength: 0)
            }
            .shadow(color: .black.opacity(light ? 0 : 0.2), radius: 8)
        }
        .frame(width: 1440, height: 900)
        .clipped()
    }
}

private struct MenuBar: View {
    var ink: Color = .white

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(ink == .white ? 0.18 : 0.04))
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
                Text(verbatim: "NotchPrompter").fontWeight(.bold)
                // The app's real menu titles, in the words macOS uses for the language.
                ForEach([StandardMenuTitle.file, StandardMenuTitle.edit,
                         String(localized: "Prompter", comment: "Menu bar menu with the prompter commands"),
                         StandardMenuTitle.window, StandardMenuTitle.help], id: \.self) { Text(verbatim: $0) }
                Spacer()
                Image(systemName: "text.aligncenter")
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(verbatim: ScreenshotRenderer.content.clock)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
        }
        .frame(height: 34)
    }
}

/// The main rows of the menu beside the record button, for the record screenshot. The whole menu
/// is too tall to read at App Store size; these are the same controls with the app's own texts.
private struct RecordShotForm: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.recordingMode) {
                    Text("Camera", comment: "Recording mode: film yourself").tag(RecordingMode.camera)
                    Text("Screen", comment: "Recording mode: record the screen").tag(RecordingMode.screen)
                    Text("Camera and screen", comment: "Recording mode: both, in two movies").tag(RecordingMode.both)
                } label: { Text("Record") }
                CameraPreviewSection(cameraID: "")
            }
            Section {
                Picker(selection: $settings.screenLight) {
                    Text("As it is", comment: "Screen light option: leave the screen as it is").tag(ScreenLight.off)
                    Text("Soft light", comment: "Screen light option: fill the screen with warm white").tag(ScreenLight.light)
                    Text("Black", comment: "Screen light option: fill the screen with black").tag(ScreenLight.dark)
                } label: { Text("Screen while recording") }
                Toggle("Save a transcript with each take", isOn: $settings.saveTranscripts)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An iPhone around a simulator capture, for the sync screenshot.
private struct PhoneFrame: View {
    let screen: NSImage

    var body: some View {
        GeometryReader { g in
            let bezel = g.size.height * 0.018
            Image(nsImage: screen).resizable()
                .clipShape(RoundedRectangle(cornerRadius: g.size.height * 0.07, style: .continuous))
                .padding(bezel)
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: g.size.height * 0.07 + bezel, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: g.size.height * 0.07 + bezel, style: .continuous)
                    .strokeBorder(Color(white: 0.35), lineWidth: 1.5))
        }
        .aspectRatio(screen.size.width / screen.size.height, contentMode: .fit)
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
