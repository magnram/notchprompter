// NotchPrompter — a tiny teleprompter that hangs from the MacBook notch,
// right under the camera, so you can read while looking into the lens.
//
// The bar at the bottom has restart, play, voice-follow, settings and quit. The settings
// popover holds the script file, speed, text size, voice language and pause-on-hover.
// Voice-follow listens to you and keeps the next word to say on the top line; click a
// word to jump there if it loses track.
// Drag the left/right edge, the bottom edge or a bottom corner to resize.
// Keys (click the prompter first so it has focus):
//   Space        play / pause           R       restart from top
//   V            voice-follow on / off  H       toggle pause-on-hover
//   ↑ / ↓        faster / slower        + / -   bigger / smaller text
//   ← / →        narrower / wider       ⇧↑ / ⇧↓ shorter / taller
//   ⌘O           open a text file       ⌘,      settings
//   Esc/⌘Q       quit
// You can also drop a .txt / .md file onto it, or scroll with the trackpad.

import AppKit
import AVFoundation
import NaturalLanguage
import QuartzCore
import Speech

final class PrompterPanel: NSPanel {
    weak var controller: Prompter?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Allow the window to sit over the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, controller?.handleKey(event) == true { return }
        super.sendEvent(event)
    }
}

final class RootView: NSView {
    weak var controller: Prompter?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first
        else { return false }
        return controller?.load(url: url) ?? false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { controller?.hovering = true }
    override func mouseExited(with event: NSEvent) {
        controller?.hovering = false
        if drag == nil { NSCursor.arrow.set() }
    }

    // MARK: Resize by dragging the left, right or bottom edge, or a bottom corner

    /// side: -1 = left edge, 1 = right edge, 0 = neither. bottom: the bottom edge.
    struct Grip { var side: CGFloat; var bottom: Bool }
    private let edgeSize: CGFloat = 7
    private let cornerSize: CGFloat = 22
    private var drag: (grip: Grip, start: NSPoint, width: CGFloat, height: CGFloat)?

    private func grip(at p: NSPoint) -> Grip? {
        let w = bounds.width
        if p.y < cornerSize && p.x < cornerSize { return Grip(side: -1, bottom: true) }
        if p.y < cornerSize && p.x > w - cornerSize { return Grip(side: 1, bottom: true) }
        if p.x < edgeSize { return Grip(side: -1, bottom: false) }
        if p.x > w - edgeSize { return Grip(side: 1, bottom: false) }
        if p.y < edgeSize { return Grip(side: 0, bottom: true) }
        return nil
    }

    // Claim clicks on the edges and on the text, so we can resize and jump to a word.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if bounds.contains(local), grip(at: local) != nil { return self }
        let hit = super.hitTest(point)
        if let c = controller, hit === c.text || hit === c.scroll || hit === c.scroll.contentView { return self }
        return hit
    }
    override func scrollWheel(with event: NSEvent) { controller?.scroll.scrollWheel(with: event) }

    override func mouseMoved(with event: NSEvent) {
        guard drag == nil else { return }
        guard let g = grip(at: convert(event.locationInWindow, from: nil)) else { NSCursor.arrow.set(); return }
        let position: NSCursor.FrameResizePosition
        switch (g.side, g.bottom) {
        case (-1, true): position = .bottomLeft
        case (1, true): position = .bottomRight
        case (-1, false): position = .left
        case (1, false): position = .right
        default: position = .bottom
        }
        NSCursor.frameResize(position: position, directions: .all).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        guard let g = grip(at: convert(event.locationInWindow, from: nil)) else { c.clickText(event); return }
        drag = (g, NSEvent.mouseLocation, c.width, c.height)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = drag, let c = controller else { return }
        let dx = NSEvent.mouseLocation.x - d.start.x
        let dy = NSEvent.mouseLocation.y - d.start.y
        // The panel stays centred under the camera, so width changes by twice the drag distance.
        if d.grip.side != 0 { c.setWidth(d.width + 2 * dx * d.grip.side) }
        if d.grip.bottom { c.setHeight(d.height - dy) }
    }

    override func mouseUp(with event: NSEvent) { drag = nil }
    override func layout() { super.layout(); controller?.layoutViews() }
}

final class ControlButton: NSButton {
    private let onClick: () -> Void

    init(_ symbol: String, _ tip: String, _ onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        toolTip = tip
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = NSColor(white: 1, alpha: 0.85)
        setSymbol(symbol)
        target = self
        action = #selector(fire)
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
    }
    @objc private func fire() { onClick() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Debug log for voice-follow: ~/Library/Logs/NotchPrompter.log (reset at each launch).
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NotchPrompter.log")
    private static let handle: FileHandle? = {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    static func write(_ message: String) {
        handle?.write(Data("\(time.string(from: Date()))  \(message)\n".utf8))
    }
}

/// Streams microphone audio into Apple's speech recogniser and reports the words heard so far.
final class VoiceListener {
    /// All words heard in the current recognition task (partial results included),
    /// with a number that changes each time a new task starts counting from zero.
    var onWords: (_ task: Int, _ words: [String]) -> Void = { _, _ in }
    private var taskNumber = 0
    var onStatus: (String) -> Void = { _ in }
    var onStopped: () -> Void = {}
    /// Words from the script, to help the recogniser with names and unusual words.
    var hints: [String] = []
    private(set) var running = false

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    /// On-Mac recognition is faster and private, but needs Dictation turned on in System Settings.
    private var onDevice = false
    private var quickErrors = 0
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?  // guarded by lock (read on the audio thread)
    private var _level: CGFloat = 0                              // guarded by lock (written on the audio thread)

    /// Microphone loudness from 0 (silence) to 1 (loud speech), updated about 40 times a second.
    var level: CGFloat {
        lock.lock(); defer { lock.unlock() }
        return running ? _level : 0
    }

    static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return CGFloat(min(1, max(0, (db + 55) / 40)))   // -55 dB → 0, -15 dB → 1
    }

    func start(locale: String) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    return self.fail("allow Speech Recognition in System Settings")
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        granted ? self.begin(locale) : self.fail("allow the microphone in System Settings")
                    }
                }
            }
        }
    }

    private func begin(_ locale: String) {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: locale)), r.isAvailable else {
            return fail("speech recognition isn't available for \(locale)")
        }
        recognizer = r
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }
            let level = VoiceListener.level(of: buffer)
            self.lock.lock(); let req = self.request; self._level = level; self.lock.unlock()
            req?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { return fail("couldn't start the microphone") }
        running = true
        onDevice = r.supportsOnDeviceRecognition
        quickErrors = 0
        languageName = Locale.current.localizedString(forIdentifier: locale) ?? locale
        restartTask()
        Log.write("start: locale \(locale), on-device \(onDevice), mic format \(input.outputFormat(forBus: 0))")
        announce()
    }

    private var languageName = ""
    private func announce() {
        onStatus("🎙 \(languageName)" + (onDevice ? "" : " · via Apple servers"))
    }

    /// Start a fresh recognition task, so earlier words are forgotten.
    func restartTask() {
        guard running, let recognizer else { return }
        task?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = onDevice
        req.taskHint = .dictation
        req.addsPunctuation = false
        req.contextualStrings = hints
        lock.lock(); request = req; lock.unlock()
        taskNumber += 1
        let number = taskNumber
        Log.write("task \(number) started (on-device \(onDevice))")
        let started = CACurrentMediaTime()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.running, self.currentRequest === req else { return }
                if let result {
                    self.quickErrors = 0
                    self.onWords(number, result.bestTranscription.segments.map(\.substring))
                }
                // Tasks end after a long pause or at a time limit; keep listening with a new one.
                if let error {
                    let e = error as NSError
                    Log.write("task \(number) error \(e.domain) \(e.code): \(e.localizedDescription)")
                    if self.onDevice {
                        // Usually "Siri and Dictation are disabled": use Apple's servers instead.
                        self.onDevice = false
                        self.announce()
                        self.restartTask()
                        return
                    }
                    // An error right after starting means the recogniser is broken, not just idle.
                    self.quickErrors = CACurrentMediaTime() - started < 1.5 ? self.quickErrors + 1 : 0
                    if self.quickErrors >= 5 {
                        return self.fail("speech recognition keeps failing (\(e.localizedDescription))")
                    }
                    // Wait a moment, so a recogniser that keeps failing doesn't spin.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if self.currentRequest === req { self.restartTask() }
                    }
                } else if result?.isFinal == true {
                    Log.write("task \(number) finished")
                    self.restartTask()
                }
            }
        }
    }

    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    func stop() {
        guard running else { return }
        running = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.lock(); request?.endAudio(); request = nil; _level = 0; lock.unlock()
        task?.cancel()
        task = nil
    }

    private func fail(_ message: String) {
        stop()
        onStatus(message)
        onStopped()
    }
}

/// Five small bars that bounce with the microphone level, like an audio indicator.
final class LevelMeter: NSView {
    private let bars = (0..<5).map { _ in CALayer() }
    private let weights: [CGFloat] = [0.55, 0.8, 1, 0.8, 0.55]
    private let barWidth: CGFloat = 3, gap: CGFloat = 2.5, maxHeight: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.backgroundColor = NSColor(white: 1, alpha: 0.9).cgColor
            bar.cornerRadius = barWidth / 2
            layer?.addSublayer(bar)
        }
        setFrameSize(intrinsicContentSize)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap, height: maxHeight)
    }

    /// level: 0…1. time drives a small wobble so the bars look alive while you talk.
    func update(level: CGFloat, time: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            let wobble = 0.75 + 0.25 * CGFloat(sin(time * (9 + Double(i) * 2.3) + Double(i)))
            // Silence shows as small dots, so you can still see the mic is on.
            let h = max(barWidth, maxHeight * weights[i] * level * wobble)
            bar.frame = NSRect(x: CGFloat(i) * (barWidth + gap), y: (maxHeight - h) / 2, width: barWidth, height: h)
        }
        CATransaction.commit()
    }
}

/// The popover behind the settings button: script file, speed, text size, voice, pause-on-hover.
final class SettingsController: NSViewController {
    unowned let prompter: Prompter
    private let docLabel = NSTextField(labelWithString: "")
    private let speedSlider = NSSlider(value: 30, minValue: 5, maxValue: 200, target: nil, action: nil)
    private let speedValue = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider(value: 20, minValue: 12, maxValue: 60, target: nil, action: nil)
    private let sizeValue = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton()
    private let hoverCheck = NSButton(checkboxWithTitle: "Pause while the mouse is over the prompter",
                                      target: nil, action: nil)
    private let locales: [Locale] = SFSpeechRecognizer.supportedLocales().sorted {
        (Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
            < (Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
    }

    init(prompter: Prompter) {
        self.prompter = prompter
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.textColor = .secondaryLabelColor
            return l
        }
        func icon(_ name: String) -> NSImageView {
            let v = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)!)
            v.contentTintColor = .secondaryLabelColor
            return v
        }
        func row(_ views: NSView...) -> NSStackView {
            let s = NSStackView(views: views)
            s.spacing = 8
            return s
        }

        docLabel.lineBreakMode = .byTruncatingMiddle
        docLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let open = NSButton(title: "Open…", target: self, action: #selector(openFile))
        open.controlSize = .small

        for (slider, action) in [(speedSlider, #selector(speedChanged)), (sizeSlider, #selector(sizeChanged))] {
            slider.target = self
            slider.action = action
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        for v in [speedValue, sizeValue] {
            v.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            v.alignment = .right
            v.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        languagePopup.controlSize = .small
        languagePopup.addItem(withTitle: "Automatic")
        languagePopup.menu?.addItem(.separator())
        languagePopup.addItems(withTitles: locales.map {
            Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
        })
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        hoverCheck.target = self
        hoverCheck.action = #selector(hoverChanged)

        let grid = NSGridView(views: [
            [label("Script"), row(docLabel, open)],
            [label("Speed"), row(icon("tortoise.fill"), speedSlider, icon("hare.fill"), speedValue)],
            [label("Text size"), row(icon("textformat.size.smaller"), sizeSlider, icon("textformat.size.larger"), sizeValue)],
            [label("Voice language"), languagePopup],
            [NSGridCell.emptyContentView, hoverCheck],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            docLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 230),
        ])
        view = container
        sync()
    }

    /// Update the controls from the prompter (keys can change the values too).
    func sync() {
        guard isViewLoaded else { return }
        docLabel.stringValue = prompter.scriptName
        speedSlider.doubleValue = Double(prompter.speed)
        speedValue.stringValue = "\(Int(prompter.speed))"
        sizeSlider.doubleValue = Double(prompter.fontSize)
        sizeValue.stringValue = "\(Int(prompter.fontSize))"
        let detected = Locale.current.localizedString(forIdentifier: prompter.detectedLocale) ?? prompter.detectedLocale
        languagePopup.item(at: 0)?.title = "Automatic (\(detected))"
        if prompter.voiceLanguage == Prompter.automatic {
            languagePopup.selectItem(at: 0)
        } else if let i = locales.firstIndex(where: { $0.identifier == prompter.voiceLanguage }) {
            languagePopup.selectItem(at: i + 2)
        }
        hoverCheck.state = prompter.pauseOnHover ? .on : .off
    }

    @objc private func openFile() { prompter.openFile() }
    @objc private func speedChanged() { prompter.speed = CGFloat(speedSlider.doubleValue.rounded()) }
    @objc private func sizeChanged() { prompter.fontSize = CGFloat(sizeSlider.doubleValue.rounded()) }
    @objc private func languageChanged() {
        let i = languagePopup.indexOfSelectedItem
        prompter.voiceLanguage = i == 0 ? Prompter.automatic : locales[i - 2].identifier
    }
    @objc private func hoverChanged() { prompter.pauseOnHover = hoverCheck.state == .on }
}

final class Prompter: NSObject, NSPopoverDelegate {
    let panel: PrompterPanel
    let root = RootView()
    let scroll: NSScrollView
    let text: NSTextView
    let hud = NSTextField(labelWithString: "")
    let fade = CAGradientLayer()
    let screen: NSScreen
    let notchHeight: CGFloat
    let defaults = UserDefaults.standard

    var offset: CGFloat = 0
    var lastTick = CACurrentMediaTime()
    var hudHideWork: DispatchWorkItem?
    let bar = NSStackView()
    var playButton: ControlButton!
    var micButton: ControlButton!
    var settingsButton: ControlButton!
    let popover = NSPopover()
    var settings: SettingsController!
    var hovering = false { didSet { updateBar() } }
    var playing = false { didSet { updateBar() } }

    // Voice-follow state
    let voice = VoiceListener()
    let meter = LevelMeter()
    var shownLevel: CGFloat = 0
    var listening = false {
        didSet {
            updateBar()
            updateProgress()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                meter.animator().alphaValue = listening ? 1 : 0
            }
        }
    }
    /// The script's words (normalised for matching) and where they are in the text.
    var words: [(norm: String, range: NSRange)] = []
    /// Index of the next word to say.
    var cursor = 0
    /// The last heard word (index in the current recognition task) that moved the cursor.
    var lastUsedSpoken = -1
    var heardTask = 0

    var script: String { didSet { defaults.set(script, forKey: "script"); applyText() } }
    var scriptName: String { didSet { defaults.set(scriptName, forKey: "scriptName"); settings?.sync() } }
    var speed: CGFloat { didSet { defaults.set(Double(speed), forKey: "speed"); settings?.sync() } }  // points / second
    var fontSize: CGFloat { didSet { defaults.set(Double(fontSize), forKey: "fontSize"); applyText(); settings?.sync() } }
    var width: CGFloat { didSet { defaults.set(Double(width), forKey: "width"); placeWindow() } }
    var height: CGFloat { didSet { defaults.set(Double(height), forKey: "height"); placeWindow() } }
    var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, forKey: "pauseOnHover"); settings?.sync() } }
    /// A speech locale such as "en-US", or `automatic` to use the script's language.
    var voiceLanguage: String {
        didSet {
            defaults.set(voiceLanguage, forKey: "voiceLanguage")
            settings?.sync()
            restartVoiceIfListening()
        }
    }
    static let automatic = "auto"
    var voiceLocale: String { voiceLanguage == Prompter.automatic ? detectedLocale : voiceLanguage }

    /// The speech locale that best fits the language the script is written in.
    var detectedLocale: String {
        let supported = SFSpeechRecognizer.supportedLocales()
        let fallback = supported.contains(Locale.current) ? Locale.current.identifier : "en-US"
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(script.prefix(3000)))
        guard var code = recognizer.dominantLanguage?.rawValue else { return fallback }
        if code == "no" || code == "nn" { code = "nb" }   // speech recognition has Norwegian Bokmål
        let matches = supported.filter { $0.language.languageCode?.identifier == code }
        let preferred = matches.first { $0.region == Locale.current.region }
            ?? matches.first { $0.identifier == "en-US" } ?? matches.first
        return preferred?.identifier ?? fallback
    }

    func restartVoiceIfListening() {
        guard listening else { return }
        voice.stop()
        lastUsedSpoken = -1
        voice.start(locale: voiceLocale)
    }

    static let welcome = """
    Drop a text file here, or open one from the settings button below.

    Press play to scroll at a steady speed, or press the microphone and just start reading. The text follows your voice.

    Drag the edges or bottom corners to resize. Hover over a button to see its keyboard shortcut.
    """

    override init() {
        let d = UserDefaults.standard
        func num(_ key: String, _ fallback: Double) -> CGFloat {
            CGFloat(d.object(forKey: key) as? Double ?? fallback)
        }
        script = d.string(forKey: "script") ?? Prompter.welcome
        scriptName = d.string(forKey: "scriptName") ?? "Welcome text"
        speed = num("speed", 30)
        fontSize = num("fontSize", 20)
        width = max(Prompter.minWidth, num("width", 440))
        height = max(Prompter.minHeight, num("height", 150))
        pauseOnHover = d.object(forKey: "pauseOnHover") as? Bool ?? true
        voiceLanguage = d.string(forKey: "voiceLanguage") ?? Prompter.automatic

        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        notchHeight = screen.safeAreaInsets.top

        panel = PrompterPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        scroll = NSTextView.scrollableTextView()
        text = scroll.documentView as! NSTextView
        super.init()

        panel.controller = self
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = .none           // hide from screen sharing / recording
        panel.hidesOnDeactivate = false

        root.controller = self
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        root.layer?.cornerRadius = 20
        root.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // round bottom only
        root.registerForDraggedTypes([.fileURL])
        panel.contentView = root

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.wantsLayer = true
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.12, 0.8, 1]
        scroll.layer?.mask = fade
        root.addSubview(scroll)

        _ = text.layoutManager   // use TextKit 1: we need word positions and temporary colours
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 18, height: 6)
        text.unregisterDraggedTypes()

        hud.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        hud.textColor = NSColor(white: 1, alpha: 0.55)
        hud.alphaValue = 0
        root.addSubview(hud)

        meter.alphaValue = 0
        meter.update(level: 0, time: 0)
        root.addSubview(meter)

        settings = SettingsController(prompter: self)
        popover.contentViewController = settings
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        voice.onWords = { [unowned self] task, heard in follow(heard, task: task) }
        voice.onStatus = { [unowned self] msg in showHUD(msg, for: 3) }
        voice.onStopped = { [unowned self] in listening = false }

        buildBar()
        applyText()
        placeWindow()

        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: Layout

    static let minWidth: CGFloat = 260
    static let minHeight: CGFloat = 100

    func placeWindow() {
        let sf = screen.frame
        let top = notchHeight > 0 ? sf.maxY : screen.visibleFrame.maxY
        panel.setFrame(NSRect(x: sf.midX - width / 2, y: top - height, width: width, height: height), display: true)
    }

    func layoutViews() {
        let b = root.bounds
        // Text starts right below the notch — as close to the camera as possible.
        scroll.frame = NSRect(x: 0, y: 0, width: b.width, height: b.height - notchHeight)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = scroll.bounds
        CATransaction.commit()
        let barSize = bar.fittingSize
        bar.frame = NSRect(x: (b.width - barSize.width) / 2, y: 8, width: barSize.width, height: barSize.height)
        hud.sizeToFit()
        // Status text sits beside the notch, or above the button bar on screens without one.
        let hudY = notchHeight > 0 ? b.height - (notchHeight + hud.frame.height) / 2 : bar.frame.maxY + 4
        hud.frame.origin = NSPoint(x: b.width - hud.frame.width - 14, y: hudY)
        // Mic level meter sits on the other side of the notch.
        let m = meter.frame.size
        let meterY = notchHeight > 0 ? b.height - (notchHeight + m.height) / 2 : b.height - m.height - 8
        meter.frame.origin = NSPoint(x: 16, y: meterY)
    }

    // MARK: Button bar

    func buildBar() {
        playButton = ControlButton("play.fill", "Play / pause (Space)") { [unowned self] in togglePlay() }
        micButton = ControlButton("mic", "Follow my voice (V)") { [unowned self] in toggleVoice() }
        settingsButton = ControlButton("slider.horizontal.3", "Script, speed, text size and voice (⌘,)") { [unowned self] in
            toggleSettings()
        }
        let restartButton = ControlButton("backward.end.fill", "Back to the top (R)") { [unowned self] in restart() }
        let quit = ControlButton("xmark", "Quit (Esc)") { NSApp.terminate(nil) }

        bar.orientation = .horizontal
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.95).cgColor
        bar.layer?.cornerRadius = 13
        [restartButton, playButton, micButton, settingsButton, quit].forEach(bar.addArrangedSubview)
        bar.setCustomSpacing(10, after: micButton)
        root.addSubview(bar)
        updateBar()
    }

    func updateBar() {
        playButton?.setSymbol(playing ? "pause.fill" : "play.fill")
        micButton?.setSymbol(listening ? "mic.fill" : "mic")
        micButton?.contentTintColor = listening ? .systemRed : NSColor(white: 1, alpha: 0.85)
        // Visible while idle, hovered or while settings are open; hidden while reading.
        let visible = hovering || (!playing && !listening) || popover.isShown
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            bar.animator().alphaValue = visible ? 1 : 0
        }
    }

    func toggleSettings() {
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate(ignoringOtherApps: true)   // so a click elsewhere closes the popover
        settings.sync()
        popover.show(relativeTo: settingsButton.bounds, of: settingsButton, preferredEdge: .minY)
        updateBar()
    }

    func popoverDidClose(_ notification: Notification) { updateBar() }

    func applyText() {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineSpacing = fontSize * 0.25
        p.paragraphSpacing = fontSize * 0.6
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: p,
        ]
        // Trailing blank lines let the last sentence scroll all the way up.
        let body = script + String(repeating: "\n", count: 10)
        text.textStorage?.setAttributedString(NSAttributedString(string: body, attributes: attrs))

        let oldCount = words.count
        words = []
        let ns = script as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { w, range, _, _ in
            if let w { self.words.append((Prompter.normalise(w), range)) }
        }
        if words.count != oldCount { cursor = 0 }
        cursor = min(cursor, words.count)
        // Longer words help the recogniser most (names, jargon).
        voice.hints = Array(Set(words.map { ns.substring(with: $0.range) }.filter { $0.count >= 6 }).prefix(100))
        updateProgress()
    }

    // MARK: Scrolling

    func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastTick)
        lastTick = now

        let clip = scroll.contentView
        if abs(clip.bounds.origin.y - offset) > 1.5 { offset = clip.bounds.origin.y }  // user scrolled manually

        if listening {
            // Level meter: jump up quickly, fall back slowly.
            let raw = voice.level
            shownLevel = raw > shownLevel ? shownLevel + (raw - shownLevel) * min(1, dt * 30) : max(raw, shownLevel - dt * 2)
            meter.update(level: shownLevel, time: now)
            // Glide quickly to put the next word to say on the top line.
            let target = voiceTarget()
            if abs(target - offset) > 0.5 { scrollTo(offset + (target - offset) * min(1, dt * 12)) }
            return
        }
        guard playing, !(pauseOnHover && hovering) else { return }

        let maxY = max(0, text.frame.height - clip.bounds.height)
        offset = min(maxY, offset + speed * dt)
        scrollTo(offset)
        if offset >= maxY { playing = false; showHUD("■ end") }
    }

    func scrollTo(_ y: CGFloat) {
        offset = y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: Voice-follow

    static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Loose word match: exact, a partly heard word, or one letter off in a longer word.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.count >= 3 && b.count >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count] <= 1
    }

    /// Move the cursor to just after the script word that the latest heard words line up with.
    func follow(_ segments: [String], task: Int) {
        let heard = segments.flatMap { $0.split(separator: " ") }.map { Prompter.normalise(String($0)) }
            .filter { !$0.isEmpty }
        // Each heard word may move the cursor once; later partial results repeat the same words.
        // A new recognition task counts heard words from zero again.
        if task != heardTask { heardTask = task; lastUsedSpoken = -1 }
        // The recogniser sometimes revises its guess into fewer words; let the newest one count again.
        if heard.count - 1 < lastUsedSpoken { lastUsedSpoken = heard.count - 2 }
        let before = cursor
        defer {
            let next = words.isEmpty ? "" : words[cursor..<min(cursor + 4, words.count)].map(\.norm).joined(separator: " ")
            Log.write("heard(\(task)): …\(heard.suffix(6).joined(separator: " "))  cursor \(before)→\(cursor)  next: \(next)")
        }
        guard heard.count - 1 > lastUsedSpoken, let last = heard.last, !words.isEmpty else { return }
        let tail = heard.suffix(5).dropLast()

        let lo = max(0, cursor - 1), hi = min(words.count - 1, cursor + 40)
        guard lo <= hi else { return }
        var best = -1, bestScore = 0.0
        for p in lo...hi where Prompter.similar(last, words[p].norm) {
            // Count how many of the words heard just before also line up, allowing a
            // skipped script word or an extra spoken word ("uh").
            var matches = 1, i = p - 1
            for w in tail.reversed() where i >= 0 {
                if Prompter.similar(w, words[i].norm) { matches += 1; i -= 1 }
                else if i >= 1 && Prompter.similar(w, words[i - 1].norm) { matches += 1; i -= 2 }
            }
            // Jumping further ahead needs more evidence.
            let distance = p - cursor
            let needed = distance <= 2 ? 1 : distance <= 8 ? 2 : 3
            guard matches >= needed else { continue }
            let score = Double(matches) - Double(abs(distance)) * 0.02
            if score > bestScore { bestScore = score; best = p }
        }
        guard best >= 0, best + 1 > cursor else { return }
        cursor = best + 1
        lastUsedSpoken = heard.count - 1
        updateProgress()
    }

    /// Scroll offset that puts the line with the next word just below the top fade.
    func voiceTarget() -> CGFloat {
        guard let lm = text.layoutManager, let tc = text.textContainer, !words.isEmpty else { return offset }
        let range = words[min(cursor, words.count - 1)].range
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let line = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        return max(0, line.minY + text.textContainerOrigin.y - scroll.bounds.height * 0.12 - 2)
    }

    /// Dim the words already said.
    func updateProgress() {
        guard let lm = text.layoutManager, let length = text.textStorage?.length else { return }
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        guard listening, cursor > 0, !words.isEmpty else { return }
        let end = NSMaxRange(words[min(cursor, words.count) - 1].range)
        lm.addTemporaryAttribute(.foregroundColor, value: NSColor(white: 1, alpha: 0.3),
                                 forCharacterRange: NSRange(location: 0, length: end))
    }

    /// Forget what was heard so far, e.g. after the cursor was moved by hand.
    func resyncVoice() {
        lastUsedSpoken = -1
        voice.restartTask()
    }

    func toggleVoice() {
        if listening {
            voice.stop()
            listening = false
            showHUD("voice off")
        } else {
            playing = false
            listening = true
            lastUsedSpoken = -1
            voice.start(locale: voiceLocale)
        }
    }

    /// While following the voice, a click on a word makes it the next word to say.
    func clickText(_ e: NSEvent) {
        guard listening, !words.isEmpty else { return }
        let index = text.characterIndexForInsertion(at: text.convert(e.locationInWindow, from: nil))
        cursor = words.firstIndex { NSMaxRange($0.range) > index } ?? words.count - 1
        updateProgress()
        resyncVoice()
        showHUD("from here")
    }

    // MARK: Input

    func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""

        if cmd {
            switch ch {
            case "q": NSApp.terminate(nil)
            case "o": openFile()
            case ",": toggleSettings()
            case "=", "+": changeFont(2)
            case "-": changeFont(-2)
            default: return false
            }
            return true
        }

        switch e.keyCode {
        case 49: togglePlay()
        case 53: if popover.isShown { popover.performClose(nil) } else { NSApp.terminate(nil) }
        case 126 where shift: changeHeight(-20)
        case 125 where shift: changeHeight(20)
        case 126: changeSpeed(5)
        case 125: changeSpeed(-5)
        case 123: changeWidth(-20)
        case 124: changeWidth(20)
        default:
            switch ch {
            case "r": restart()
            case "v": toggleVoice()
            case "h": toggleHoverPause()
            case "=", "+": changeFont(2)
            case "-": changeFont(-2)
            default: return false
            }
        }
        return true
    }

    // MARK: Actions (shared by keys and buttons)

    func togglePlay() {
        if listening { voice.stop(); listening = false }
        playing.toggle()
        if playing && pauseOnHover && hovering { showHUD("▶ starts when the mouse leaves") }
        else { showHUD(playing ? "▶ \(Int(speed))" : "❚❚") }
    }
    func restart() {
        cursor = 0
        updateProgress()
        scrollTo(0)
        if listening { resyncVoice() }
        showHUD("⟲ top")
    }
    func changeSpeed(_ d: CGFloat) { speed = min(200, max(5, speed + d)); showHUD("speed \(Int(speed))") }
    func changeFont(_ d: CGFloat) { fontSize = min(60, max(12, fontSize + d)); showHUD("size \(Int(fontSize))") }
    func setWidth(_ w: CGFloat) { width = min(1000, max(Prompter.minWidth, w.rounded())) }
    func setHeight(_ h: CGFloat) { height = min(600, max(Prompter.minHeight, h.rounded())) }
    func changeWidth(_ d: CGFloat) { setWidth(width + d) }
    func changeHeight(_ d: CGFloat) { setHeight(height + d) }
    func toggleHoverPause() {
        pauseOnHover.toggle()
        showHUD(pauseOnHover ? "hover pauses: on" : "hover pauses: off")
    }

    func openFile() {
        popover.performClose(nil)
        let op = NSOpenPanel()
        op.allowedContentTypes = [.plainText, .text]
        op.allowsOtherFileTypes = true
        NSApp.activate(ignoringOtherApps: true)
        if op.runModal() == .OK, let url = op.url { _ = load(url: url) }
        panel.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func load(url: URL) -> Bool {
        let s: String
        if url.pathExtension.lowercased() == "rtf",
           let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            s = a.string
        } else if let plain = try? String(contentsOf: url, encoding: .utf8) {
            s = plain
        } else { showHUD("can't read file"); return false }
        script = s
        scriptName = url.lastPathComponent
        settings?.sync()
        if voiceLanguage == Prompter.automatic { restartVoiceIfListening() }
        playing = false
        restart()
        showHUD(url.lastPathComponent)
        return true
    }

    func showHUD(_ msg: String, for seconds: Double = 1.2) {
        hud.stringValue = msg
        layoutViews()
        hud.alphaValue = 1
        hudHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self?.hud.animator().alphaValue = 0
            }
        }
        hudHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let prompter = Prompter()
if CommandLine.arguments.count > 1 {
    prompter.load(url: URL(fileURLWithPath: CommandLine.arguments[1]))
}
app.activate(ignoringOtherApps: true)
prompter.panel.makeKeyAndOrderFront(nil)
app.run()
