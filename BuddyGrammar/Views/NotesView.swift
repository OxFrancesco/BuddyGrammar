import SwiftUI

struct NotesView: View {
    @Bindable var model: AppModel

    private var selectedNote: NoteItem? {
        guard let selectedNoteID = model.selectedNoteID else { return nil }
        return model.notesStore.note(id: selectedNoteID)
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Notes")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Spacer()
                    Button {
                        model.addNote()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Add note")
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                if model.notesStore.notes.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $model.selectedNoteID) {
                        ForEach(model.notesStore.notes) { note in
                            NoteRow(note: note)
                                .tag(note.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 230)
        } detail: {
            if let selectedNote {
                NoteEditorView(
                    note: selectedNote,
                    title: noteTitleBinding(for: selectedNote.id),
                    content: noteContentBinding(for: selectedNote.id),
                    hotkey: noteHotkeyBinding(for: selectedNote.id),
                    conflictLabel: model.noteHotkeyConflictLabel(for: selectedNote.id, hotkey: selectedNote.hotkey),
                    onPaste: {
                        model.pasteNote(selectedNote)
                    },
                    onCopy: {
                        model.copyNoteToClipboard(selectedNote)
                    },
                    onDelete: {
                        model.deleteSelectedNote()
                    }
                )
                .id(selectedNote.id)
            } else {
                ContentUnavailableView("Select a Note", systemImage: "note.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(NeoTheme.background)
        .foregroundStyle(NeoTheme.foreground)
        .onAppear {
            if model.selectedNoteID == nil {
                model.selectedNoteID = model.notesStore.notes.first?.id
            }
        }
    }

    private func noteTitleBinding(for id: UUID) -> Binding<String> {
        Binding {
            model.notesStore.note(id: id)?.title ?? ""
        } set: { title in
            guard var note = model.notesStore.note(id: id) else { return }
            note.title = title
            model.notesStore.update(note)
        }
    }

    private func noteContentBinding(for id: UUID) -> Binding<String> {
        Binding {
            model.notesStore.note(id: id)?.content ?? ""
        } set: { content in
            guard var note = model.notesStore.note(id: id) else { return }
            note.content = content
            model.notesStore.update(note)
        }
    }

    private func noteHotkeyBinding(for id: UUID) -> Binding<HotkeyDescriptor?> {
        Binding {
            model.notesStore.note(id: id)?.hotkey
        } set: { hotkey in
            guard var note = model.notesStore.note(id: id) else { return }
            note.hotkey = hotkey
            model.notesStore.update(note)
        }
    }
}

private struct NoteRow: View {
    let note: NoteItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .lineLimit(1)
                Text(note.hotkey?.displayString ?? note.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct NoteEditorView: View {
    let note: NoteItem
    @Binding var title: String
    @Binding var content: String
    @Binding var hotkey: HotkeyDescriptor?
    let conflictLabel: String?
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .black, design: .rounded))

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(content.isEmpty)
                .help("Copy note")

                Button {
                    onPaste()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .disabled(content.isEmpty)
                .help("Paste note")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete note")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcut")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(NeoTheme.mutedForeground)
                HotkeyRecorderView(hotkey: $hotkey, conflictLabel: conflictLabel)
            }
            .padding(14)
            .modifier(NeoBrutalistCard())

            TextEditor(text: $content)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(NeoTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                        .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
                )
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
