import AppKit

extension NSScreen {
    /// Stays the same for a display across restarts and reconnects, unlike its display number.
    var uuid: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The screen for the prompter: the chosen one while it is connected, otherwise the one with
    /// the notch (the camera is above it), otherwise the main screen.
    static func forPrompter(_ chosen: String) -> NSScreen? {
        screens.first { !chosen.isEmpty && $0.uuid == chosen }
            ?? screens.first { $0.safeAreaInsets.top > 0 }
            ?? main ?? screens.first
    }
}

/// The connected screens, for the "Show on" picker.
final class Displays: ObservableObject {
    static let shared = Displays()

    struct Display: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @Published private(set) var all: [Display] = []

    private init() {
        update()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.update() }
    }

    private func update() {
        all = NSScreen.screens.compactMap { s in s.uuid.map { Display(id: $0, name: s.localizedName) } }
    }
}
