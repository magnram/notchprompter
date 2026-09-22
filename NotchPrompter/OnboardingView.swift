import SwiftUI

/// First-launch welcome: what the app does, the microphone permission, and where the controls are.
struct OnboardingView: View {
    var onFinish: (_ startVoice: Bool) -> Void

    @State private var page = 0
    @State private var permissionProblem: String?
    @State private var authorized = VoiceListener.isAuthorized
    @State private var asking = false

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: voice
                case 2: play
                default: scripts
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .transition(.opacity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Page \(page + 1) of \(pageCount)")
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                }
                if page < pageCount - 1 {
                    Button("Continue") { withAnimation { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Try It Now") { onFinish(true) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 420)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            NotchIllustration()
                .frame(width: 300, height: 120)
            Text("Welcome to NotchPrompter").font(.largeTitle.weight(.bold))
            Text("Your script hangs right under the camera, so you can read it while you look people in the eye — in video calls, recordings and presentations.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var voice: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
                .frame(height: 70)
            Text("It follows your voice").font(.title.weight(.bold))
            Text("Press the microphone and just talk, in any language. The text moves as you read, so the next words are always right under the camera. Skip a line and it jumps ahead; pause and it waits.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Speech is recognised on your Mac and never saved.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if authorized {
                Label("Microphone allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(asking ? "Waiting…" : "Allow Microphone and Speech Recognition") {
                    asking = true
                    VoiceListener.requestPermissions { problem in
                        asking = false
                        permissionProblem = problem
                        authorized = problem == nil
                    }
                }
                .controlSize(.large)
                .disabled(asking)
            }
            if let permissionProblem {
                Text(permissionProblem).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
    }

    private var play: some View {
        VStack(spacing: 18) {
            Text("The controls").font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: 12) {
                row("mic.fill", .red, "Follow my voice", "The main mode. Click a word if you want to jump there.")
                row("record.circle", .red, "Record", "Film yourself while you read. Takes go to Movies › NotchPrompter.")
                row("play.fill", .primary, "Play", "Scrolls at a steady speed. Hover over the text to pause.")
                row("tortoise.fill", .primary, "Slower and faster", "Appear while playing. Arrow keys work too.")
                row("pencil", .primary, "Edit scripts", "Write, paste or import your scripts.")
                row("slider.horizontal.3", .primary, "Settings", "Text size, speed, voice language and more.")
            }
            Text("Drag the edges or corners of the prompter to resize it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var scripts: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .frame(height: 70)
            Text("Your scripts").font(.title.weight(.bold))
            Text("Write your scripts in the built-in editor, or import text, Markdown and Word files. Everything is saved on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("You can open NotchPrompter from the menu bar icon at any time. Let's try it with a short practice script.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint == .primary ? Color.white : tint)
                .frame(width: 34, height: 26)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// A MacBook screen edge with the prompter hanging from the notch.
struct NotchIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.blue.opacity(0.5), .purple.opacity(0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                    .fill(.black)
                    .frame(width: w * 0.55, height: h * 0.72)
                    .overlay(alignment: .center) {
                        VStack(spacing: 4) {
                            Text("look people in the eye").opacity(0.35)
                            Text("while you read your script")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 14)
                    }
                Circle().fill(Color(white: 0.2)).frame(width: 6, height: 6).padding(.top, 4)
            }
        }
        .accessibilityHidden(true)
    }
}
