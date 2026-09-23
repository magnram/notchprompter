import AppKit
import Combine
import QuartzCore
import SwiftUI
import NotchPrompterKit

final class PrompterPanel: NSPanel {
    weak var controller: Prompter?
    override var canBecomeKey: Bool { true }
    // Allow the window to sit over the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, controller?.handleKey(event) == true { return }
        super.sendEvent(event)
    }
}

/// The panel's content view: edge and corner resizing, clicks on words, file drops, hover.
final class RootView: NSView {
    weak var controller: Prompter?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first
        else { return false }
        return controller?.importAndShow(url) ?? false
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
    private var drag: (grip: Grip, start: NSPoint, width: Double, height: Double)?

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
        drag = (g, NSEvent.mouseLocation, c.settings.width, c.settings.height)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = drag, let c = controller else { return }
        let dx = NSEvent.mouseLocation.x - d.start.x
        let dy = NSEvent.mouseLocation.y - d.start.y
        // The panel stays centred under the camera, so width changes by twice the drag distance.
        if d.grip.side != 0 {
            c.settings.width = (d.width + Double(2 * dx * d.grip.side)).rounded().clamped(to: AppSettings.widthRange)
        }
        if d.grip.bottom {
            c.settings.height = (d.height - Double(dy)).rounded().clamped(to: AppSettings.heightRange)
        }
    }

    override func mouseUp(with event: NSEvent) { drag = nil }
    override func layout() { super.layout(); controller?.layoutViews() }
}

final class ControlButton: NSButton {
    private let onClick: () -> Void
    private let pointSize: CGFloat

    init(_ symbol: String, _ tip: String, size: CGFloat = 12, width: CGFloat = 24, _ onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.pointSize = size
        super.init(frame: .zero)
        toolTip = tip
        setAccessibilityLabel(tip)
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = ControlButton.normalTint
        setSymbol(symbol)
        target = self
        action = #selector(fire)
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    static let normalTint = NSColor(white: 1, alpha: 0.85)

    func setSymbol(_ name: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
    }
    @objc private func fire() { onClick() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
        setFrameSize(NSSize(width: CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap, height: maxHeight))
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }

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

/// The teleprompter that hangs from the notch.
final class Prompter: NSObject, NSPopoverDelegate {
    let settings: AppSettings
    let library: ScriptLibrary
    /// Called when the user wants to edit scripts (pencil button, empty script).
    var onOpenEditor: () -> Void = {}

    let panel: PrompterPanel
    let root = RootView()
    let scroll: NSScrollView
    let text: NSTextView
    private let hud = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let fade = CAGradientLayer()
    private let screen: NSScreen
    private let notchHeight: CGFloat
    private var subscriptions = Set<AnyCancellable>()

    private var offset: CGFloat = 0
    private var lastTick = CACurrentMediaTime()
    private var hudHideWork: DispatchWorkItem?
    private let bar = NSStackView()
    private let barBackground = NSView()
    private var playButton: ControlButton!
    private var micButton: ControlButton!
    private var speedButtons: [ControlButton] = []
    private var settingsButton: ControlButton!
    private let popover = NSPopover()
    var hovering = false { didSet { updateBar() } }
    private(set) var playing = false { didSet { updateBar() } }
    private var countdownWork: [DispatchWorkItem] = []
    private var countingDown: Bool { !countdownWork.isEmpty }

    // Recording
    private let recorder = Recorder()
    private let screenRecorder = ScreenRecorder()
    private var recordButton: ControlButton!
    private let recLabel = NSTextField(labelWithString: "")
    private let cameraPreview = CameraPreviewPanel()
    /// Filming: the camera movie, the screen movie, or both are being saved.
    var isRecording: Bool { recorder.isRecording || screenRecorder.isRecording }
    private var recordingStartedAt: Date { recorder.isRecording ? recorder.startedAt : screenRecorder.startedAt }

    // Voice-follow
    private let voice = VoiceListener()
    private let meter = LevelMeter()
    private var shownLevel: CGFloat = 0
    private var matcher = VoiceMatcher()
    private var shownScriptID: UUID?
    private var shownText = ""
    private var lastAdvance = CACurrentMediaTime()
    private var lostHintShown = false
    private(set) var listening = false {
        didSet {
            updateBar()
            updateProgress()
            layoutViews()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                meter.animator().alphaValue = listening ? 1 : 0
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    init(settings: AppSettings = .shared, library: ScriptLibrary = .shared) {
        self.settings = settings
        self.library = library
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
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel(String(localized: "Teleprompter"))

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
        hud.textColor = NSColor(white: 1, alpha: 0.6)
        hud.alignment = .right
        hud.alphaValue = 0
        root.addSubview(hud)

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .bold)
        countdownLabel.textColor = .white
        countdownLabel.alignment = .center
        countdownLabel.isHidden = true
        root.addSubview(countdownLabel)

        meter.alphaValue = 0
        meter.update(level: 0, time: 0)
        root.addSubview(meter)

        popover.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, compact: true))
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        voice.onWords = { [unowned self] task, heard in
            if matcher.follow(heard, task: task) {
                lastAdvance = CACurrentMediaTime()
                updateProgress()
            }
        }
        voice.onStatus = { [unowned self] msg in showHUD(msg, for: 3) }
        voice.onStopped = { [unowned self] in listening = false }
        voice.onPermissionProblem = { [unowned self] message, url in
            if isRecording { stopRecording() }
            showPermissionAlert(String(localized: "Allow access to follow your voice"),
                                message + "\n\n" + String(localized: "You can still use Play to scroll at a steady speed."), url)
        }
        voice.onNeedsDictation = { [unowned self] in
            let alert = NSAlert()
            alert.messageText = String(localized: "Turn on Dictation to follow your voice on this Mac")
            alert.informativeText = String(localized: "NotchPrompter recognises speech on your Mac, so your voice never leaves it. macOS only allows this when Dictation is on.\n\nTurn on Dictation in System Settings → Keyboard, then press the microphone again. Or let Apple's servers recognise your speech instead.")
            alert.addButton(withTitle: String(localized: "Open Keyboard Settings"))
            alert.addButton(withTitle: String(localized: "Use Apple's Servers"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            NSApp.activate()
            switch alert.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(VoiceListener.dictationSettings)
            case .alertSecondButtonReturn:
                settings.onDeviceOnly = false
                startVoice()
            default: break
            }
        }
        // With the camera, its movie is the take; the screen movie only reports problems.
        screenRecorder.onFinished = { [unowned self] url, problem in
            if discardTake { url.map { try? FileManager.default.removeItem(at: $0) }; return }
            if takeMode.usesCamera {
                if let problem { showHUD(problem, for: 5) }
            } else {
                takeFinished(url, problem)
            }
        }
        recorder.onFinished = { [unowned self] url, problem in takeFinished(url, problem) }

        recLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        recLabel.textColor = .systemRed
        recLabel.isHidden = true
        root.addSubview(recLabel)

        buildBar()
        observe()
        placeWindow()

        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func takeFinished(_ url: URL?, _ problem: String?) {
        updateBar()
        layoutViews()
        if discardTake { url.map { try? FileManager.default.removeItem(at: $0) }; return }
        if let problem { showHUD(problem, for: 5); return }
        guard let url else { return }
        // The first time, show where takes go. After that, a short note is enough.
        let key = "hasRevealedRecording"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        showHUD(String(localized: "Saved in Movies › NotchPrompter",
                       comment: "Use the Finder name of the Movies folder in this language"), for: 4)
    }

    private func observe() {
        // Publishers fire before the property changes, so use the value they send.
        settings.$fontSize.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.renderText() }
        }.store(in: &subscriptions)
        settings.$width.combineLatest(settings.$height).sink { [weak self] w, h in
            self?.placeWindow(width: w, height: h)
        }.store(in: &subscriptions)
        settings.$hideFromScreenSharing.sink { [weak self] hide in
            self?.panel.sharingType = hide ? .none : .readOnly
        }.store(in: &subscriptions)
        settings.$voiceLanguage.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.restartVoiceIfListening() }
        }.store(in: &subscriptions)
        library.$scripts.combineLatest(library.$activeID).sink { [weak self] scripts, id in
            let script = scripts.first { $0.id == id }
            DispatchQueue.main.async { self?.show(script) }
        }.store(in: &subscriptions)
    }

    // MARK: Showing and hiding

    func showPanel() {
        placeWindow()
        panel.orderFrontRegardless()
    }

    func hidePanel() {
        stopAll()
        popover.performClose(nil)
        panel.orderOut(nil)
    }

    func togglePanel() { isVisible ? hidePanel() : showPanel() }

    /// Stop scrolling, listening and recording.
    func stopAll() {
        cancelCountdown()
        playing = false
        if listening { voice.stop(); listening = false }
        if isRecording || pendingRecording { stopRecording() }
    }

    func showPermissionAlert(_ title: String, _ message: String, _ url: URL) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
    }

    // MARK: Layout

    private func placeWindow(width: Double? = nil, height: Double? = nil) {
        let w = CGFloat(width ?? settings.width), h = CGFloat(height ?? settings.height)
        let sf = screen.frame
        let top = notchHeight > 0 ? sf.maxY : screen.visibleFrame.maxY
        panel.setFrame(NSRect(x: sf.midX - w / 2, y: top - h, width: w, height: h), display: true)
    }

    /// The notch's left and right edges in the panel's coordinates, with a little room for its
    /// rounded corners. Nil on screens without a notch.
    private var notchSpan: (left: CGFloat, right: CGFloat)? {
        guard notchHeight > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return nil }
        let x0 = panel.frame.minX
        return (l.maxX - x0 - 8, r.minX - x0 + 8)
    }

    private var hudShowing = false

    func layoutViews() {
        let b = root.bounds
        let margin: CGFloat = 16
        let notch = notchSpan
        // Beside the notch there is room for short things; the rest goes in a row at the bottom, so
        // the first line of text stays right under the camera.
        let leftEar = notch.map { $0.left - margin } ?? 0          // usable width left of the notch
        let rightEar = notch.map { b.width - margin - $0.right } ?? 0

        // Left: the level meter, then the recording time.
        let m = meter.frame.size
        recLabel.sizeToFit()
        let showMeter = listening, showRec = !recLabel.isHidden
        let leftWidth = (showMeter ? m.width : 0) + (showMeter && showRec ? 10 : 0) + (showRec ? recLabel.frame.width : 0)
        let leftFits = leftWidth <= leftEar

        // Right: status messages, wrapped when they need the row below the notch.
        hud.preferredMaxLayoutWidth = 0
        hud.maximumNumberOfLines = 1
        hud.sizeToFit()
        let hudFits = hud.frame.width <= rightEar
        if !hudFits {
            hud.maximumNumberOfLines = 0
            hud.preferredMaxLayoutWidth = b.width - 2 * margin
            hud.frame.size = hud.fittingSize
        }

        // The bottom row is only there while something needs it.
        let rowItems: [CGFloat] = (leftFits || leftWidth == 0 ? [] : [max(m.height, recLabel.frame.height)])
            + (hudFits || !hudShowing ? [] : [hud.frame.height])
        let rowHeight = rowItems.max().map { $0 + 6 } ?? 0
        let stripY = b.height - notchHeight                       // bottom of the notch strip
        let rowY: CGFloat = 4                                      // bottom of the bottom row

        // Text starts right below the notch — as close to the camera as possible.
        let textY = rowHeight > 0 ? rowY + rowHeight : 0
        scroll.frame = NSRect(x: 0, y: textY, width: b.width, height: max(0, stripY - textY))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = scroll.bounds
        CATransaction.commit()
        let barSize = bar.fittingSize
        barBackground.frame = NSRect(x: (b.width - barSize.width) / 2, y: 8 + textY, width: barSize.width, height: barSize.height)
        bar.frame = barBackground.bounds
        updateFade()
        countdownLabel.sizeToFit()
        countdownLabel.frame = NSRect(x: 0, y: (scroll.frame.height - countdownLabel.frame.height) / 2 + 10,
                                      width: b.width, height: countdownLabel.frame.height)

        // Centre of the strip beside the notch, or of the bottom row.
        func midY(_ h: CGFloat, inStrip: Bool) -> CGFloat {
            inStrip ? stripY + (notchHeight - h) / 2 : rowY + (rowHeight - h) / 2
        }
        meter.frame.origin = NSPoint(x: 18, y: midY(m.height, inStrip: leftFits))
        let recX = showMeter ? meter.frame.maxX + 10 : 18
        recLabel.frame.origin = NSPoint(x: recX, y: midY(recLabel.frame.height, inStrip: leftFits))
        hud.frame.origin = NSPoint(x: b.width - hud.frame.width - margin, y: midY(hud.frame.height, inStrip: hudFits))
    }

    // MARK: Button bar

    private func buildBar() {
        // Tooltips name the key that does the same; the keys are the same in every language.
        let restartButton = ControlButton("backward.end.fill", String(localized: "Back to the top (R)")) { [unowned self] in
            restart()
        }
        micButton = ControlButton("mic.fill", Self.micTip, size: 14, width: 30) { [unowned self] in
            toggleVoice()
        }
        recordButton = ControlButton("record.circle", Self.recordTip, size: 13) { [unowned self] in
            toggleRecording()
        }
        playButton = ControlButton("play.fill", String(localized: "Scroll at a steady speed (Space)")) { [unowned self] in
            togglePlay()
        }
        speedButtons = [
            ControlButton("tortoise.fill", String(localized: "Slower (↓)")) { [unowned self] in changeSpeed(-5) },
            ControlButton("hare.fill", String(localized: "Faster (↑)")) { [unowned self] in changeSpeed(5) },
        ]
        let edit = ControlButton("pencil", String(localized: "Edit scripts (E)")) { [unowned self] in onOpenEditor() }
        settingsButton = ControlButton("slider.horizontal.3", String(localized: "Text size, speed and voice (⌘,)")) {
            [unowned self] in toggleSettings()
        }
        let hide = ControlButton("xmark", String(localized: "Hide the prompter (⇧⌘P)"), size: 10, width: 20) { [unowned self] in
            hidePanel()
            showHideTipOnce()
        }

        bar.orientation = .horizontal
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        // A plain view draws the pill: a stack view's own layer background isn't reliably drawn.
        barBackground.wantsLayer = true
        barBackground.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        barBackground.layer?.cornerRadius = 13
        barBackground.layer?.shadowColor = NSColor.black.cgColor
        barBackground.layer?.shadowOpacity = 1
        barBackground.layer?.shadowRadius = 10
        for v in [restartButton, micButton!, recordButton!, playButton!] + speedButtons + [edit, settingsButton!, hide] { bar.addArrangedSubview(v) }
        bar.setCustomSpacing(10, after: speedButtons.last!)
        bar.setCustomSpacing(10, after: restartButton)
        bar.setCustomSpacing(8, after: settingsButton)
        barBackground.addSubview(bar)
        root.addSubview(barBackground)
        updateBar()
    }

    private func updateBar() {
        guard playButton != nil else { return }
        playButton.setSymbol(playing || countingDown ? "pause.fill" : "play.fill")
        // Listening: a white mic on a red pill. Off: a red mic, so it stands out as the main button.
        micButton.wantsLayer = true
        micButton.layer?.cornerRadius = 9
        micButton.layer?.backgroundColor = listening ? NSColor.systemRed.cgColor : NSColor.clear.cgColor
        micButton.contentTintColor = listening ? .white : NSColor(calibratedRed: 1, green: 0.38, blue: 0.36, alpha: 1)
        micButton.toolTip = listening ? String(localized: "Stop following my voice (V)") : Self.micTip
        micButton.setAccessibilityLabel(micButton.toolTip)
        recordButton.setSymbol(isRecording ? "stop.circle.fill" : "record.circle")
        recordButton.contentTintColor = isRecording ? .systemRed : ControlButton.normalTint
        recordButton.toolTip = isRecording ? String(localized: "Stop recording (C)") : Self.recordTip
        recordButton.setAccessibilityLabel(recordButton.toolTip)
        // Speed only matters while scrolling at a steady speed.
        let showSpeed = playing || countingDown
        if speedButtons.first?.isHidden == showSpeed {
            speedButtons.forEach { $0.isHidden = !showSpeed }
            layoutViews()
        }
        // Visible while idle, hovered or while settings are open; hidden while reading.
        let visible = hovering || (!playing && !listening && !countingDown) || popover.isShown
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            barBackground.animator().alphaValue = visible ? 1 : 0
        }
        barVisible = visible
        updateFade()
    }

    private var barVisible = true
    private static let micTip = String(localized: "Follow my voice (V)")
    private static let recordTip = String(localized: "Record video of yourself (C)")

    /// Fade the text out above the bar while it shows, so the bar never covers a line you need.
    /// The mask's gradient runs from the top (0) to the bottom (1).
    private func updateFade() {
        let h = max(scroll.bounds.height, 1)
        let hidden = barVisible ? min(0.5, (barBackground.frame.maxY - scroll.frame.minY + 2) / h) : 0
        fade.locations = [0, 0.12, 0.8 - hidden, 1 - hidden].map { NSNumber(value: Double($0)) }
    }

    /// The first time the prompter is hidden, say how to get it back.
    private func showHideTipOnce() {
        let key = "hasSeenHideTip"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = String(localized: "The prompter is hidden")
        alert.informativeText = String(localized: "To bring it back, click the NotchPrompter icon in the menu bar, click the app in the Dock, or press ⇧⌘P.")
        NSApp.activate()
        alert.runModal()
    }

    func toggleSettings() {
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate()   // so a click elsewhere closes the popover
        popover.show(relativeTo: settingsButton.bounds, of: settingsButton, preferredEdge: .minY)
        updateBar()
    }

    func popoverDidClose(_ notification: Notification) { updateBar() }

    // MARK: Text

    private static let emptyHint = String(localized: "This script is empty.\nClick the pencil below to write it.")

    private func show(_ script: Script?) {
        let newScript = script?.id != shownScriptID
        let newText = script?.text ?? ""
        guard newScript || newText != shownText else { return }
        shownScriptID = script?.id
        shownText = newText
        if newScript { matcher.cursor = 0; stopAll() }
        matcher.setText(newText)
        voice.hints = Array(Set(matcher.words.map { (newText as NSString).substring(with: $0.range) }
            .filter { $0.count >= 6 }).prefix(100))
        renderText()
        if newScript {
            scrollTo(0)
            if listening { restartVoiceIfListening() }
        }
    }

    private var isEmpty: Bool { matcher.words.isEmpty }

    private func renderText() {
        let size = CGFloat(settings.fontSize)
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineSpacing = size * 0.25
        p.paragraphSpacing = size * 0.6
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: isEmpty ? NSColor(white: 1, alpha: 0.45) : NSColor.white,
            .paragraphStyle: p,
        ]
        // Trailing blank lines let the last sentence scroll all the way up.
        let body = (isEmpty ? Self.emptyHint : shownText) + String(repeating: "\n", count: 10)
        let styled = NSMutableAttributedString(string: body, attributes: attrs)
        // Stage directions: quieter and in italics, so it's clear they aren't read out.
        let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: size * 0.85, weight: .medium), toHaveTrait: .italicFontMask)
        for cue in matcher.cues where !isEmpty {
            styled.addAttributes([.font: italic, .foregroundColor: NSColor(white: 1, alpha: 0.5)], range: cue)
        }
        text.textStorage?.setAttributedString(styled)
        updateProgress()
    }

    /// Dim the words already said.
    private func updateProgress() {
        guard let lm = text.layoutManager, let length = text.textStorage?.length else { return }
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        guard listening, matcher.cursor > 0, !isEmpty else { return }
        let end = matcher.saidEnd(in: shownText as NSString)
        lm.addTemporaryAttribute(.foregroundColor, value: NSColor(white: 1, alpha: 0.3),
                                 forCharacterRange: NSRange(location: 0, length: end))
    }

    // MARK: Scrolling

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastTick)
        lastTick = now
        guard panel.isVisible else { return }
        updateRecLabel()

        let clip = scroll.contentView
        if abs(clip.bounds.origin.y - offset) > 1.5 { offset = clip.bounds.origin.y }  // user scrolled manually

        if listening {
            // Level meter: jump up quickly, fall back slowly.
            var raw = voice.level
            #if DEBUG
            if let debugLevel { raw = debugLevel }
            #endif
            shownLevel = raw > shownLevel ? shownLevel + (raw - shownLevel) * min(1, dt * 30) : max(raw, shownLevel - dt * 2)
            meter.update(level: shownLevel, time: now)
            if shownLevel < 0.3 { quietSince = now }
            // Talking for a while without the text moving: explain how to get back on track.
            if !lostHintShown, now - lastAdvance > 6, now - quietSince > 2.5 {
                lostHintShown = true
                showHUD(String(localized: "Lost? Click the word you're on"), for: 4)
            }
            // Glide quickly to put the next word to say on the top line.
            let target = lineOffset(forWord: matcher.cursor)
            if abs(target - offset) > 0.5 { scrollTo(offset + (target - offset) * min(1, dt * 12)) }
            return
        }
        guard playing, !(settings.pauseOnHover && hovering) else { return }

        let maxY = max(0, text.frame.height - clip.bounds.height)
        scrollTo(min(maxY, offset + CGFloat(settings.speed) * dt))
        if offset >= maxY { playing = false; showHUD(String(localized: "■ The end")) }
    }
    private var quietSince = CACurrentMediaTime()
    #if DEBUG
    var debugLevel: CGFloat?
    #endif

    private func scrollTo(_ y: CGFloat) {
        offset = y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Scroll offset that puts the line with a word just below the top fade.
    private func lineOffset(forWord index: Int) -> CGFloat {
        guard let lm = text.layoutManager, let tc = text.textContainer, !isEmpty else { return 0 }
        let range = matcher.words[min(index, matcher.words.count - 1)].range
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let line = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        return max(0, line.minY + text.textContainerOrigin.y - scroll.bounds.height * 0.12 - 2)
    }

    // MARK: Voice-follow

    private var voiceLocale: String {
        settings.voiceLanguage == AppSettings.automaticLanguage
            ? VoiceListener.detectLocale(for: shownText) : settings.voiceLanguage
    }

    func toggleVoice() {
        if listening {
            voice.stop()
            listening = false
            showHUD(String(localized: "Voice off"))
        } else {
            startVoice()
        }
    }

    func startVoice() {
        guard !isEmpty else { onOpenEditor(); return }
        cancelCountdown()
        playing = false
        showPanel()
        listening = true
        matcher.resetHeard()
        lastAdvance = CACurrentMediaTime()
        lostHintShown = false
        voice.onDeviceOnly = settings.onDeviceOnly
        voice.start(locale: voiceLocale)
    }

    private func restartVoiceIfListening() {
        guard listening else { return }
        voice.stop()
        matcher.resetHeard()
        voice.onDeviceOnly = settings.onDeviceOnly
        voice.start(locale: voiceLocale)
    }

    /// A click on a word makes it the next word to say (voice) or the top line (play).
    func clickText(_ e: NSEvent) {
        if isEmpty { onOpenEditor(); return }
        let index = text.characterIndexForInsertion(at: text.convert(e.locationInWindow, from: nil))
        guard let word = matcher.wordIndex(atCharacter: index) else { return }
        matcher.cursor = word
        if listening {
            matcher.resetHeard()
            lastAdvance = CACurrentMediaTime()
            updateProgress()
            showHUD(String(localized: "From here", comment: "After clicking a word: voice-follow continues from here"))
        } else {
            scrollTo(lineOffset(forWord: word))
        }
    }

    // MARK: Play mode

    func togglePlay() {
        if playing || countingDown { cancelCountdown(); playing = false; showHUD(String(localized: "❚❚ Paused")); return }
        guard !isEmpty else { onOpenEditor(); return }
        if listening { voice.stop(); listening = false }
        showPanel()
        let atEnd = offset >= max(0, text.frame.height - scroll.contentView.bounds.height) - 1
        if atEnd { scrollTo(0) }
        if settings.countdown { startCountdown(then: startPlaying) } else { startPlaying() }
    }

    private func startPlaying() {
        playing = true
        if settings.pauseOnHover && hovering { showHUD(String(localized: "▶ Starts when the mouse leaves"), for: 2) }
        else { showHUD(String(localized: "▶ Speed \(Int(settings.speed))")) }
    }

    private func startCountdown(then action: @escaping () -> Void = {}) {
        for (i, n) in ["3", "2", "1"].enumerated() {
            let work = DispatchWorkItem { [weak self] in
                self?.countdownLabel.stringValue = n
                self?.countdownLabel.isHidden = false
                self?.layoutViews()
            }
            countdownWork.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.7, execute: work)
        }
        let go = DispatchWorkItem { [weak self] in
            guard let self else { return }
            countdownWork = []
            countdownLabel.isHidden = true
            action()
        }
        countdownWork.append(go)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1, execute: go)
        updateBar()
    }

    private func cancelCountdown() {
        countdownWork.forEach { $0.cancel() }
        countdownWork = []
        countdownLabel.isHidden = true
        updateBar()
    }

    // MARK: Recording

    func toggleRecording() {
        if isRecording || pendingRecording { stopRecording(); return }
        guard !isEmpty else { onOpenEditor(); return }
        let mode = settings.recordingMode
        // Pending from the first press: a second press while macOS asks for access cancels,
        // instead of starting a second take.
        pendingRecording = true
        discardTake = false
        Recorder.requestAccess(camera: mode.usesCamera) { [weak self] problem in
            guard let self, pendingRecording else { return }
            if let problem {
                pendingRecording = false
                return showPermissionAlert(String(localized: "Allow access to record"), problem.message, problem.url)
            }
            if mode.usesScreen && !ScreenRecorder.requestAccess() {
                pendingRecording = false
                return showPermissionAlert(String(localized: "Allow screen recording"),
                    String(localized: "Turn on NotchPrompter in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen NotchPrompter. Or choose to record only the camera in Settings → Recording."),
                    ScreenRecorder.settingsURL)
            }
            cancelCountdown()
            playing = false
            showPanel()
            takeMode = mode
            // Voice-follow hears the recording's microphone, so only one part of the app reads it:
            // the camera recorder, or the screen capture when there is no camera.
            if listening { voice.stop(); listening = false }
            recorder.onAudio = mode.usesCamera ? { [weak voice] in voice?.append($0) } : nil
            screenRecorder.onAudio = mode.usesCamera ? nil : { [weak voice] in voice?.append($0) }
            // Wake the camera first, so filming starts exactly when the countdown ends.
            showHUD(mode.usesCamera ? String(localized: "Starting camera…") : String(localized: "Starting screen recording…"))
            prepareAll(mode) { [weak self] problem in
                guard let self else { return }
                // Stopped while the camera was waking up: turn it off again.
                guard pendingRecording else { recorder.stop(); screenRecorder.stop(); cameraPreview.hide(); return }
                if let problem {
                    pendingRecording = false
                    recorder.stop(); screenRecorder.stop(); cameraPreview.hide()
                    showHUD(problem, for: 5); updateBar(); return
                }
                // Speech recognition takes a moment to load, so start it now: it is ready at "go".
                voice.useExternalAudio = true
                startVoice()
                // The movies also need a moment before the first frames are saved. Start them a
                // little before "go", so a take never misses the first words.
                let startFiles = { [weak self] in
                    guard let self, pendingRecording, !isRecording else { return }
                    let name = Recorder.takeName()
                    if mode.usesScreen {
                        screenRecorder.record(name: mode.usesCamera
                            ? String(localized: "\(name) Screen", comment: "File name of the screen movie that goes with a take")
                            : name)
                    }
                    if mode.usesCamera {
                        recorder.record(name: name) { [weak self] problem in
                            guard let self else { return }
                            if let problem { showHUD(problem, for: 5) }
                            updateBar()
                            layoutViews()
                        }
                    }
                }
                let go = { [weak self] in
                    guard let self, pendingRecording else { return }
                    startFiles()
                    pendingRecording = false
                    recLabel.isHidden = false
                    layoutViews()
                    updateBar()
                }
                if settings.countdown {
                    startCountdown(then: go)
                    let early = DispatchWorkItem { startFiles() }
                    countdownWork.append(early)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: early)
                } else {
                    go()
                }
            }
        }
    }

    private var pendingRecording = false
    /// The take was stopped during the countdown: its movies were only just started, so delete them.
    private var discardTake = false
    /// What the current (or last) take records.
    private var takeMode = RecordingMode.camera

    /// Wake the camera and the screen capture that `mode` needs. `ready` gets the first problem, if any.
    private func prepareAll(_ mode: RecordingMode, ready: @escaping (String?) -> Void) {
        let screenPart = { [weak self] in
            guard let self else { return }
            guard mode.usesScreen else { return ready(nil) }
            // Leave the prompter (when hidden from recordings) and the camera preview out of the screen movie.
            var hidden = [cameraPreview.windowNumber]
            if settings.hideFromScreenSharing { hidden.append(panel.windowNumber) }
            screenRecorder.prepare(screen: panel.screen, hiddenWindows: hidden, microphone: !mode.usesCamera, ready: ready)
        }
        guard mode.usesCamera else { return screenPart() }
        recorder.prepare(cameraID: settings.cameraID) { [weak self] problem in
            guard let self else { return }
            guard problem == nil else { return ready(problem) }
            // Show the camera during the countdown, so you can check how you look before it films.
            if settings.showCameraPreview, let screen = panel.screen {
                cameraPreview.show(recorder.session, beside: panel.frame, on: screen)
            }
            screenPart()
        }
    }

    /// Stop the take; the movie file is finished a moment later.
    func stopRecording(completion: (() -> Void)? = nil) {
        if pendingRecording { discardTake = true }
        pendingRecording = false
        cancelCountdown()
        recLabel.isHidden = true
        layoutViews()
        if listening { voice.stop(); listening = false }
        voice.useExternalAudio = false
        cameraPreview.hide()
        // Wait for both movies before `completion` (used when quitting).
        var left = 2
        let done = { left -= 1; if left == 0 { completion?() } }
        recorder.stop(completion: done)
        screenRecorder.stop(completion: done)
        updateBar()
    }

    private func updateRecLabel() {
        guard isRecording else { return }
        let t = Int(Date().timeIntervalSince(recordingStartedAt))
        let dot = t % 2 == 0 ? "●" : "○"
        let time = String(format: "%d:%02d", t / 60, t % 60)
        let text = String(localized: "\(dot) REC \(time)",
                          comment: "Recording indicator beside the notch: a blinking dot, REC and the time. Keep it short.")
        if recLabel.stringValue != text {
            recLabel.stringValue = text
            layoutViews()
        }
    }

    func restart() {
        matcher.cursor = 0
        updateProgress()
        scrollTo(0)
        if listening { matcher.resetHeard(); lastAdvance = CACurrentMediaTime() }
        showHUD(String(localized: "⟲ Top", comment: "Back at the top of the script"))
    }

    func changeSpeed(_ d: Double) {
        settings.speed = (settings.speed + d).clamped(to: AppSettings.speedRange)
        showHUD(String(localized: "Speed \(Int(settings.speed))"))
    }

    func changeFontSize(_ d: Double) {
        settings.fontSize = (settings.fontSize + d).clamped(to: AppSettings.fontSizeRange)
        showHUD(String(localized: "Text size \(Int(settings.fontSize))"))
    }

    @discardableResult
    func importAndShow(_ url: URL) -> Bool {
        guard let script = try? library.importFile(at: url) else { showHUD(String(localized: "Can't read that file")); return false }
        library.activeID = script.id
        showHUD(script.displayTitle)
        return true
    }

    // MARK: Keys (when the prompter has keyboard focus)

    func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""

        if cmd {
            switch ch {
            case ",": toggleSettings()
            case "=", "+": changeFontSize(2)
            case "-": changeFontSize(-2)
            default: return false   // let the main menu handle it
            }
            return true
        }

        switch e.keyCode {
        case 49: togglePlay()
        case 53:
            if popover.isShown { popover.performClose(nil) } else { stopAll() }
        case 126 where shift: settings.height = (settings.height - 20).clamped(to: AppSettings.heightRange)
        case 125 where shift: settings.height = (settings.height + 20).clamped(to: AppSettings.heightRange)
        case 126: changeSpeed(5)
        case 125: changeSpeed(-5)
        case 123: settings.width = (settings.width - 20).clamped(to: AppSettings.widthRange)
        case 124: settings.width = (settings.width + 20).clamped(to: AppSettings.widthRange)
        default:
            switch ch {
            case "r": restart()
            case "v": toggleVoice()
            case "c": toggleRecording()
            case "e": onOpenEditor()
            case "h":
                settings.pauseOnHover.toggle()
                showHUD(settings.pauseOnHover ? String(localized: "Hover pauses: on") : String(localized: "Hover pauses: off"))
            case "=", "+": changeFontSize(2)
            case "-": changeFontSize(-2)
            default: return false
            }
        }
        return true
    }

    func showHUD(_ msg: String, for seconds: Double = 1.4) {
        hud.stringValue = msg
        hudShowing = true
        layoutViews()
        hud.alphaValue = 1
        hudHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self?.hud.animator().alphaValue = 0
            } completionHandler: {
                self?.hudShowing = false
                self?.layoutViews()
            }
        }
        hudHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

#if DEBUG
/// Puts the prompter in a fixed state for screenshots, without the microphone.
extension Prompter {
    enum DebugStage { case idle, reading(word: Int), playing }

    func debugStage(_ stage: DebugStage, hud message: String? = nil) {
        stopAll()
        hovering = false
        switch stage {
        case .idle:
            matcher.cursor = 0
            scrollTo(0)
        case .reading(let word):
            matcher.cursor = word
            debugLevel = 0.75
            listening = true
            lostHintShown = true
            scrollTo(lineOffset(forWord: word))
        case .playing:
            playing = true
            hovering = true   // shows the bar with the speed buttons, and pauses scrolling
            scrollTo(lineOffset(forWord: 30))
        }
        updateProgress()
        hud.alphaValue = 0; hudShowing = false; layoutViews()
        if let message { showHUD(message, for: 60) }
    }
}
#endif
