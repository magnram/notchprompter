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
