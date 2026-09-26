import AVFoundation
import AppKit
import SwiftUI
import NotchPrompterKit

/// A view that says when it can be seen, so a preview only uses the camera or microphone then.
class VisibilityTrackingView: NSView {
    /// Called with true when the view is on screen, and false when its window closes, hides or
    /// is covered. The Settings window is kept after closing, so it can't rely on being removed.
    var onVisible: ((Bool) -> Void)? {
        didSet { updateVisible() }
    }
    private var observers: [NSObjectProtocol] = []
    private var visible = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    self?.updateVisible(closing: note.name == NSWindow.willCloseNotification)
                })
            }
        }
        updateVisible()
    }

    private func updateVisible(closing: Bool = false) {
        let now = !closing && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        guard now != visible, let onVisible else { return }
        visible = now
        onVisible(now)
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// Shows a capture session's camera, mirrored like a mirror (and like FaceTime), so moving
/// left moves left on screen.
final class CameraPreviewNSView: VisibilityTrackingView {
    let preview = AVCaptureVideoPreviewLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { fatalError() }

    var session: AVCaptureSession? {
        get { preview.session }
        set {
            preview.session = newValue
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
}

/// A small floating camera preview beside the prompter while a take is prepared and filmed.
/// It can be dragged anywhere, and it is never in screen recordings or screen sharing.
final class CameraPreviewPanel {
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 224, height: 126),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let view = CameraPreviewNSView(frame: NSRect(x: 0, y: 0, width: 224, height: 126))
    private var moved = false

    init() {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        panel.contentView = view
        panel.setAccessibilityLabel(String(localized: "Camera preview"))
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, panel.isVisible else { return }
            moved = true
        }
    }

    var windowNumber: Int { panel.windowNumber }
    var isVisible: Bool { panel.isVisible }

    /// Show `session` next to `prompter`, on the side with more room, unless it was dragged away.
    func show(_ session: AVCaptureSession, beside prompter: NSRect, on screen: NSScreen) {
        view.session = session
        if !moved || !screen.frame.intersects(panel.frame) {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            let right = prompter.maxX + 12
            let x = right + size.width <= visible.maxX ? right : prompter.minX - 12 - size.width
            panel.setFrameOrigin(NSPoint(x: x, y: visible.maxY - size.height - 8))
            moved = false
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        view.session = nil
    }
}

/// A live camera preview for Settings, with its own session, so the camera can be aimed before a take.
struct CameraPreview: NSViewRepresentable {
    let cameraID: String

    final class Coordinator {
        let session = AVCaptureSession()
        let queue = DispatchQueue(label: "com.magnusramm.NotchPrompter.settings-preview")
        var cameraID: String?
        /// Only film while the preview can be seen.
        var visible = false

        func use(_ id: String) {
            guard id != cameraID else { return }
            cameraID = id
            guard visible else { return }
            start()
        }

        func setVisible(_ on: Bool) {
            visible = on
            if on { start() } else { stop() }
        }

        private func start() {
            guard let id = cameraID else { return }
            let camera = Recorder.cameras.first { $0.uniqueID == id } ?? AVCaptureDevice.default(for: .video)
            queue.async { [session] in
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                if let camera, let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
            }
        }

        func stop() { queue.async { [session] in session.stopRunning() } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView(frame: .zero)
        view.session = context.coordinator.session
        context.coordinator.use(cameraID)
        view.onVisible = { [weak coordinator = context.coordinator] in coordinator?.setVisible($0) }
        return view
    }

    func updateNSView(_ view: CameraPreviewNSView, context: Context) {
        context.coordinator.use(cameraID)
    }

    static func dismantleNSView(_ view: CameraPreviewNSView, coordinator: Coordinator) {
        view.onVisible = nil
        view.session = nil
        coordinator.setVisible(false)
    }
}

/// The microphone's level, or a button to allow the microphone first.
struct MicrophoneLevelSection: View {
    let microphoneID: String
    @State private var status = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        #if DEBUG
        // Screenshots: a still bar, so the microphone stays off.
        if ScreenshotRenderer.outputFolder != nil {
            LabeledContent("Input level") { LevelBarStill(level: 0.62).frame(height: 6) }
        } else { live }
        #else
        live
        #endif
    }

    @ViewBuilder private var live: some View {
        switch status {
        case .authorized:
            LabeledContent("Input level") {
                MicrophoneLevel(microphoneID: microphoneID).frame(height: 6)
            }
        case .notDetermined:
            LabeledContent("Input level") {
                Button("Test Microphone") {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { status = AVCaptureDevice.authorizationStatus(for: .audio) }
                    }
                }
            }
        default:
            LabeledContent("NotchPrompter can't use the microphone.") {
                Button("Open System Settings") { NSWorkspace.shared.open(VoiceListener.microphoneSettings) }
            }
        }
    }
}

/// The Settings preview, or a button to allow the camera first.
struct CameraPreviewSection: View {
    let cameraID: String
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            #if DEBUG
            // Screenshots: a picture from a file, so the camera stays off.
            if ScreenshotRenderer.outputFolder != nil {
                if let still = ScreenshotRenderer.cameraStill {
                    Image(nsImage: still).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else { live }
            #else
            live
            #endif
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var live: some View {
        Group {
            switch status {
            case .authorized:
                CameraPreview(cameraID: cameraID)
            case .notDetermined:
                Button("Show Camera Preview") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { status = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                VStack(spacing: 8) {
                    Text("NotchPrompter can't use the camera.")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") { NSWorkspace.shared.open(Recorder.cameraSettings) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#if DEBUG
/// The level bar as a picture, for screenshots.
private struct LevelBarStill: View {
    let level: CGFloat
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) { Capsule().fill(.green).frame(width: g.size.width * level) }
        }
    }
}
#endif

/// A live level bar for the chosen microphone, so you can see it hears you before a take.
struct MicrophoneLevel: NSViewRepresentable {
    let microphoneID: String

    final class Coordinator: NSObject {
        let session = AVCaptureSession()
        private let output = AVCaptureAudioDataOutput()
        let queue = DispatchQueue(label: "com.magnusramm.NotchPrompter.settings-mic")
        var microphoneID: String?
        var visible = false
        weak var view: LevelBarView?
        private var timer: Timer?

        func use(_ id: String) {
            guard id != microphoneID else { return }
            microphoneID = id
            if visible { start() }
        }

        func setVisible(_ on: Bool) {
            visible = on
            if on { start() } else { stop() }
        }

        private func start() {
            guard let id = microphoneID else { return }
            let mic = Recorder.microphone(id)
            queue.async { [session, output] in
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                if let mic, let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
                    session.addInput(input)
                }
                // The level is only measured while audio flows to an output.
                if session.outputs.isEmpty, session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
            }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                guard let self else { return }
                let channels = output.connection(with: .audio)?.audioChannels ?? []
                let db = channels.map(\.averagePowerLevel).max() ?? -160
                // -50 dB (quiet room) to -10 dB (loud speech) fills the bar.
                view?.level = CGFloat(((db + 50) / 40).clamped(to: 0...1))
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            view?.level = 0
            queue.async { [session] in session.stopRunning() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LevelBarView {
        let view = LevelBarView()
        context.coordinator.view = view
        context.coordinator.use(microphoneID)
        view.onVisible = { [weak coordinator = context.coordinator] in coordinator?.setVisible($0) }
        return view
    }

    func updateNSView(_ view: LevelBarView, context: Context) {
        context.coordinator.use(microphoneID)
    }

    static func dismantleNSView(_ view: LevelBarView, coordinator: Coordinator) {
        view.onVisible = nil
        coordinator.setVisible(false)
    }
}

final class LevelBarView: VisibilityTrackingView {
    /// 0…1.
    var level: CGFloat = 0 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 6) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()
        guard level > 0 else { return }
        let fill = NSRect(x: 0, y: 0, width: max(bounds.height, bounds.width * level), height: bounds.height)
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: fill, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}
