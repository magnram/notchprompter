import Foundation
import NotchPrompterKit

extension ScriptLibrary {
    static let shared = ScriptLibrary { Script(title: welcomeTitle, text: welcomeText) }

    static let welcomeTitle = String(localized: "Welcome", comment: "Title of the built-in practice script")

    /// The practice script shown on first launch. Voice-follow detects the language from the text,
    /// so it is translated in full. Keep the stage direction in brackets: it shows that notes in
    /// brackets aren't read out.
    static let welcomeText = String(localized: "welcomeScript", defaultValue: """
    Welcome to NotchPrompter.

    Press the microphone below and read this out loud. The text follows your voice, so the next words are always right under your camera.

    Keep your eyes up here. To the people watching, it looks like you are talking straight to them.

    If you lose your place, click the word you are on, and the prompter continues from there.

    Notes to yourself go in brackets. (take a breath) You don't read them out loud, and the prompter moves past them.

    Prefer a steady pace? Press play instead. Hover over the text to pause, and use the tortoise and the hare to change the speed.

    To write your own script, click the pencil. Your scripts are saved on this Mac.

    That is all. Have a great recording!
    """, comment: "The built-in practice script. Keep the paragraphs and the note in brackets, translated.")
}
