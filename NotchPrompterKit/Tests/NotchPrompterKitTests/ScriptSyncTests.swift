import XCTest
@testable import NotchPrompterKit

/// iCloud key-value storage in memory, shared by two "devices".
private final class MemoryCloud: KeyValueCloud {
    var values: [String: Data] = [:]
    var keys: [String] { Array(values.keys) }
    func data(forKey key: String) -> Data? { values[key] }
    func store(_ data: Data?, forKey key: String) { values[key] = data }
    func synchronize() -> Bool { true }
}

final class ScriptSyncTests: XCTestCase {
    private let welcome = "Welcome, read this out loud."
    private var folder: URL!
    private var cloud: MemoryCloud!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cloud = MemoryCloud()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func device(_ name: String) -> ScriptLibrary {
        let welcome = welcome
        return ScriptLibrary(fileURL: folder.appendingPathComponent("\(name).json"),
                             welcome: { Script(title: "Welcome", text: welcome) },
                             keepsLocal: { $0.text == welcome }, cloud: cloud)
    }

    func testNewScriptReachesTheOtherDevice() {
        let mac = device("mac"), phone = device("phone")
        let script = mac.add(title: "Talk", text: "Hello everyone")
        mac.saveNow()
        phone.cloudChanged()
        XCTAssertEqual(phone.script(script.id)?.text, "Hello everyone")
    }

    func testThePracticeScriptStaysOnTheDevice() {
        let mac = device("mac")
        mac.saveNow()
        XCTAssertTrue(cloud.values.isEmpty)
        let phone = device("phone")
        phone.cloudChanged()
        XCTAssertEqual(phone.scripts.count, 1)
    }

    func testTheLaterChangeWins() {
        let mac = device("mac"), phone = device("phone")
        let script = mac.add(title: "Talk", text: "First")
        mac.saveNow()
        phone.cloudChanged()
        phone.setText("Second", of: script.id)
        phone.saveNow()
        mac.cloudChanged()
        XCTAssertEqual(mac.script(script.id)?.text, "Second")

        // An older copy doesn't undo it.
        var old = script
        old.text = "Old"
        old.modified = Date(timeIntervalSinceNow: -3600)
        cloud.values["script." + script.id.uuidString] = try? JSONEncoder().encode(old)
        mac.cloudChanged()
        XCTAssertEqual(mac.script(script.id)?.text, "Second")
    }

    func testDeletingRemovesItEverywhere() {
        let mac = device("mac"), phone = device("phone")
        let script = mac.add(title: "Talk", text: "Hello")
        mac.saveNow()
        phone.cloudChanged()
        phone.delete(script.id)
        phone.saveNow()
        mac.cloudChanged()
        XCTAssertNil(mac.script(script.id))
        // And it doesn't come back from the Mac's next save.
        mac.saveNow()
        phone.cloudChanged()
        XCTAssertNil(phone.script(script.id))
    }

    func testScriptsSurviveARestart() {
        let mac = device("mac")
        let script = mac.add(title: "Talk", text: "Hello")
        mac.saveNow()
        let phone = device("phone")
        phone.cloudChanged()
        let phoneAgain = device("phone")
        XCTAssertEqual(phoneAgain.script(script.id)?.text, "Hello")
    }
}
