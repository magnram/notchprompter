import AppKit
import Carbon.HIToolbox
import Combine
import NotchPrompterKit

/// Shortcuts that work while another app is in front: a video call, Keynote, or the app you
/// film for a screen recording. Carbon hot keys need no Accessibility access.
/// ⌃⌥ because apps rarely use it; ⌃⌥Space is left alone, macOS uses it to switch input sources.
final class GlobalShortcuts: ObservableObject {
    static let shared = GlobalShortcuts()

    enum Action: UInt32, CaseIterable {
        case showPrompter = 1, pauseResume, record

        private var keyCode: Int {
            switch self {
            case .showPrompter: kVK_ANSI_P
            case .pauseResume: kVK_ANSI_V
            case .record: kVK_ANSI_R
            }
        }

        /// How the shortcut is written, e.g. ⌃⌥P.
        var keys: String {
            switch self {
            case .showPrompter: "⌃⌥P"
            case .pauseResume: "⌃⌥V"
            case .record: "⌃⌥R"
            }
        }

        var title: String {
            switch self {
            case .showPrompter: String(localized: "Show or hide the prompter")
            case .pauseResume: String(localized: "Pause or resume", comment: "Global shortcut: stop following the voice or scrolling, keeping the place, or carry on")
            case .record: String(localized: "Start or stop recording")
            }
        }

        fileprivate func register() -> EventHotKeyRef? {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x4E_74_50_72 /* "NtPr" */, id: rawValue)
            let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &ref)
            return status == noErr ? ref : nil
        }
    }

    /// Shortcuts that another app has already claimed.
    @Published private(set) var taken: Set<Action> = []
    var onAction: (Action) -> Void = { _ in }

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var subscription: AnyCancellable?

    private init() {}

    func start(_ settings: AppSettings) {
        subscription = settings.$globalShortcuts.removeDuplicates().sink { [weak self] on in
            on ? self?.register() : self?.unregister()
        }
    }

    private func register() {
        unregister()
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard let action = Action(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { GlobalShortcuts.shared.onAction(action) }
                return noErr
            }, 1, &type, nil, &handler)
        }
        var taken: Set<Action> = []
        for action in Action.allCases {
            if let ref = action.register() { refs.append(ref) } else { taken.insert(action) }
        }
        self.taken = taken
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        taken = []
    }
}
