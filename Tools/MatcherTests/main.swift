// Tests for VoiceMatcher. Run: Tools/test-matcher.sh
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    print(ok ? "ok   \(name)" : "FAIL \(name)")
    if !ok { failures += 1 }
}

let script = "Hi everyone and thanks for joining. Today I want to show you something we have been working on for a long time. The quick brown fox jumps over the lazy dog."

func matcher() -> VoiceMatcher { var m = VoiceMatcher(); m.setText(script); return m }
/// Feed a sentence word by word, the way partial results grow.
func speak(_ m: inout VoiceMatcher, _ text: String, task: Int = 1) {
    let words = text.split(separator: " ").map(String.init)
    for n in 1...words.count { m.follow(Array(words.prefix(n)), task: task) }
}

do {
    var m = matcher()
    speak(&m, "hi everyone and thanks for joining")
    check(m.cursor == 6, "follows a sentence word by word (cursor \(m.cursor))")
}
do {
    var m = matcher()
    speak(&m, "hi everyone uh and thanks")
    check(m.cursor == 4, "ignores a filler word (cursor \(m.cursor))")
}
do {
    var m = matcher()
    speak(&m, "hi every")
    check(m.cursor == 2, "accepts a partly heard word (cursor \(m.cursor))")
}
do {
    var m = matcher()
    speak(&m, "hi everyone")
    speak(&m, "the", task: 2)
    check(m.cursor == 2, "a single common word does not jump ahead (cursor \(m.cursor))")
}
do {
    var m = matcher()
    speak(&m, "hi everyone")
    speak(&m, "today i want to show", task: 2)
    check(m.cursor == 11, "skips ahead when several words agree (cursor \(m.cursor))")
}
do {
    var m = matcher()
    speak(&m, "hi everyone and", task: 1)
    speak(&m, "thanks for joining", task: 2)
    check(m.cursor == 6, "continues after the recogniser restarts (cursor \(m.cursor))")
}
do {
    var m = matcher()
    m.follow(["hi", "everyone", "and", "thanks"], task: 1)
    m.follow(["hi", "everyone", "and", "thanks"], task: 1)
    check(m.cursor == 4, "repeated partial results do not move twice (cursor \(m.cursor))")
}
do {
    var m = matcher()
    m.follow(["hi", "everyone"], task: 1)
    // A laggy result brings several words at once, and the newest one is misheard.
    m.follow(["hi", "everyone", "and", "thanks", "four", "joy"], task: 1)
    check(m.cursor == 4, "a burst ending in misheard words still moves (cursor \(m.cursor))")
    m.follow(["hi", "everyone", "and", "thanks", "for", "joining"], task: 1)
    check(m.cursor == 6, "the corrected words move on (cursor \(m.cursor))")
}
do {
    // Going off script with a few words that also come later must not jump there.
    var m = matcher()
    speak(&m, "hi everyone")
    speak(&m, "hi everyone so we have been", task: 1)
    check(m.cursor == 2, "a few loose words don't jump far ahead (cursor \(m.cursor))")
}
do {
    // Going back to say a sentence again: the same words come later in the script.
    var m = VoiceMatcher()
    m.setText("Most people just ignore it. You don't need to spend more. The rest comes from offers most people just scroll past.")
    speak(&m, "most people just ignore it you don't need")
    speak(&m, "most people just ignore it you don't need most people just ignore it")
    check(m.cursor == 8, "saying a sentence again doesn't jump to where it repeats (cursor \(m.cursor))")
    speak(&m, "most people just ignore it you don't need most people just ignore it you don't need to spend more")
    check(m.cursor == 11, "follows on after the sentence said again (cursor \(m.cursor))")
}
do {
    check(VoiceMatcher.similar("working", "workin"), "one letter off in a long word matches")
    check(!VoiceMatcher.similar("fox", "for"), "short different words do not match")
    check(VoiceMatcher.normalise("Joining.") == "joining", "normalise drops case and punctuation")
}
do {
    var m = matcher()
    let i = (script as NSString).range(of: "quick").location
    check(m.wordIndex(atCharacter: i + 2).map { m.words[$0].norm } == "quick", "finds the clicked word")
    m.cursor = m.wordIndex(atCharacter: i)!
    speak(&m, "quick brown fox")
    check(m.words[m.cursor - 1].norm == "fox", "follows from a clicked word")
}
do {
    // A click moves the cursor back, and the same recognition task goes on: the words it heard
    // before the click must not count again.
    var m = matcher()
    speak(&m, "hi everyone and thanks for joining")
    m.cursor = 0
    m.resetHeard()
    m.follow("hi everyone and thanks for joining".split(separator: " ").map(String.init), task: 1)
    check(m.cursor == 0, "words heard before a click don't count again (cursor \(m.cursor))")
    m.follow("hi everyone and thanks for joining hi everyone".split(separator: " ").map(String.init), task: 1)
    check(m.cursor == 2, "follows the new words after a click (cursor \(m.cursor))")
}

do {
    let text = "Hello there, friends. (pause) Now [smile] we begin." as NSString
    var m = VoiceMatcher(); m.setText(text as String)
    check(m.words.map(\.norm) == ["hello", "there", "friends", "now", "we", "begin"], "stage directions are not words to say")
    check(m.cues.count == 2, "finds (pause) and [smile]")
    speak(&m, "hello there")
    check(text.substring(to: m.saidEnd(in: text)) == "Hello there,", "the comma after a said word is said too")
    speak(&m, "hello there friends")
    check(text.substring(to: m.saidEnd(in: text)) == "Hello there, friends. (pause)", "a stage direction after the last said word is passed")
    speak(&m, "now we begin", task: 2)
    check(m.saidEnd(in: text) == text.length, "the end of the text is reached")
}
do {
    let text = "He said \"stop\" and (laughs) left." as NSString
    var m = VoiceMatcher(); m.setText(text as String)
    speak(&m, "he said")
    check(text.substring(to: m.saidEnd(in: text)) == "He said", "an opening quote belongs to the next word")
    speak(&m, "he said stop")
    check(text.substring(to: m.saidEnd(in: text)) == "He said \"stop\"", "a closing quote belongs to the said word")
}

print(failures == 0 ? "All tests passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
