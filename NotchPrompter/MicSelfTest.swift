#if DEBUG
import AppKit
import CoreAudio

/// Checks that the app lets go of the microphone when it stops listening, so the Mac's
/// microphone indicator turns off. It only uses voice-follow: it never films or records. Run: NotchPrompter -micSelfTest (prints to stdout, then quits).
enum MicSelfTest {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-micSelfTest") }

    /// Whether this process is reading from a microphone right now.
    static var usingMicrophone: Bool {
        var pid = getpid()
        var object = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object) == noErr,
              object != 0 else { return false }
        var running: UInt32 = 0
        size = 4
        address.mSelector = kAudioProcessPropertyIsRunningInput
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running)
        return running != 0
    }

    static func run(prompter: Prompter) {
        var steps: [(String, () -> Void)] = [
            ("at launch", {}),
            ("listening", { prompter.startVoice() }),
            ("after the microphone button stops listening", { prompter.toggleVoice() }),
            ("listening again", { prompter.startVoice() }),
            ("after hiding the prompter", { prompter.hidePanel() }),
            ("after starting and stopping at once", { prompter.startVoice(); prompter.toggleVoice() }),
        ]
        var failed = false
        func next() {
            guard !steps.isEmpty else {
                print(failed ? "MIC TEST FAILED" : "MIC TEST PASSED")
                fflush(stdout)
                NSApp.terminate(nil)
                return
            }
            let (name, action) = steps.removeFirst()
            action()
            // Watch the microphone for 8 seconds; judge by where it ends up.
            let start = CACurrentMediaTime()
            var timeline = ""
            var last: Bool?
            func sample() {
                let inUse = usingMicrophone
                if inUse != last { timeline += String(format: " %.1fs:%@", CACurrentMediaTime() - start, inUse ? "on" : "off"); last = inUse }
                guard CACurrentMediaTime() - start >= 8 else {
                    return DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: sample)
                }
                let expected = name.hasPrefix("listening")
                if inUse != expected { failed = true }
                print("\(inUse == expected ? "ok  " : "FAIL") \(name): microphone\(timeline)")
                fflush(stdout)
                next()
            }
            sample()
        }
        next()
    }
}
#endif
