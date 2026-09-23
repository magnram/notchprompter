import AVFoundation
import AppKit
import SwiftUI

/// Shows a capture session's camera, mirrored like a mirror (and like FaceTime), so moving
/// left moves left on screen.
final class CameraPreviewNSView: NSView {
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

/// The Settings preview, or a button to allow the camera first.
struct CameraPreviewSection: View {
    let cameraID: String
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
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
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
