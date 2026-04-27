import Foundation
import Observation

@MainActor
@Observable
final class NotesStore {
    private enum Keys {
        static let notes = "BuddyGrammar.notes"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var notes: [NoteItem] {
        didSet {
            persist(notes)
            onNotesChanged?(notes)
        }
    }

    var onNotesChanged: (([NoteItem]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notes = Self.loadNotes(from: defaults, decoder: decoder)
    }

    func addNote() -> UUID {
        let note = NoteItem()
        notes.insert(note, at: 0)
        return note.id
    }

    func update(_ note: NoteItem) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = Date()
        notes[index] = updated
    }

    func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    func note(id: UUID) -> NoteItem? {
        notes.first { $0.id == id }
    }

    func hotkeyConflict(for noteID: UUID, hotkey: HotkeyDescriptor?) -> NoteItem? {
        guard let hotkey else { return nil }
        return notes.first { note in
            note.id != noteID && note.hotkey == hotkey
        }
    }

    func notesWithHotkeys() -> [NoteItem] {
        notes.filter { $0.hotkey?.isValid == true && !$0.content.isEmpty }
    }

    private func persist(_ notes: [NoteItem]) {
        guard let data = try? encoder.encode(notes) else { return }
        defaults.set(data, forKey: Keys.notes)
    }

    private static func loadNotes(from defaults: UserDefaults, decoder: JSONDecoder) -> [NoteItem] {
        guard let data = defaults.data(forKey: Keys.notes),
              let notes = try? decoder.decode([NoteItem].self, from: data) else {
            return []
        }

        return notes
    }
}
