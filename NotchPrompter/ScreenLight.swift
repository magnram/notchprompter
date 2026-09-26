import AppKit
import NotchPrompterKit

/// Fills the whole screen behind the prompter during a camera take: a soft, warm light on your
/// face, or black so the screen doesn't shine in glasses or light up the room behind you.
/// It sits under the prompter and the camera preview, and is never in screen recordings or sharing.
final class ScreenLightPanel {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)

    init() {
        // Over the menu bar and the Dock, under the camera preview (mainMenu + 1) and the prompter (+ 2).
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.sharingType = .none
        // Clicks land on the light, not on the windows it covers.
        panel.ignoresMouseEvents = false
        panel.setAccessibilityElement(false)
    }

    var windowNumber: Int { panel.windowNumber }

    func show(_ light: ScreenLight, on screen: NSScreen) {
        guard light != .off else { return hide() }
        // Daylight white with a little warmth, which is kinder to skin than the blue of pure white.
        panel.backgroundColor = light == .light ? NSColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1) : .black
        panel.setFrame(screen.frame, display: false)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; panel.animator().alphaValue = 1 }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) { [panel] in
            // A new take may have started while it faded out.
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        }
    }
}
