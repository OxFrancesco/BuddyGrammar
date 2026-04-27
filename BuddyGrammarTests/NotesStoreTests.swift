@testable import BuddyGrammar
import XCTest

@MainActor
final class NotesStoreTests: XCTestCase {
    func testAddUpdateAndReloadNote() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = NotesStore(defaults: suite)

        let id = store.addNote()
        var note = store.note(id: id)!
        note.title = "Reply"
        note.content = "Thanks, I will take a look."
        note.hotkey = HotkeyDescriptor(keyCode: 18, modifiers: [.command, .option])
        store.update(note)

        let reloaded = NotesStore(defaults: suite)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.title, "Reply")
        XCTAssertEqual(reloaded.notes.first?.content, "Thanks, I will take a look.")
        XCTAssertEqual(reloaded.notes.first?.hotkey?.displayString, "⌥⌘1")
    }

    func testNotesWithHotkeysExcludesEmptyContent() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = NotesStore(defaults: suite)

        let emptyID = store.addNote()
        var empty = store.note(id: emptyID)!
        empty.hotkey = HotkeyDescriptor(keyCode: 18, modifiers: [.command])
        store.update(empty)

        let filledID = store.addNote()
        var filled = store.note(id: filledID)!
        filled.content = "Paste me"
        filled.hotkey = HotkeyDescriptor(keyCode: 19, modifiers: [.command])
        store.update(filled)

        XCTAssertEqual(store.notesWithHotkeys().map(\.id), [filledID])
    }
}
