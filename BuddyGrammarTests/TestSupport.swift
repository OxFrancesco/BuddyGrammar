@testable import BuddyGrammar
import Foundation

final class MockPasteboardController: PasteboardControlling {
    var changeCount: Int = 0
    var storedString: String?
    var storedSnapshot = ClipboardSnapshot(items: [])

    func readString() -> String? {
        storedString
    }

    func snapshot() -> ClipboardSnapshot {
        storedSnapshot
    }

    func restore(snapshot: ClipboardSnapshot) {
        storedSnapshot = snapshot
        storedString = snapshot.items.first?.representations["public.utf8-plain-text"].flatMap {
            String(data: $0, encoding: .utf8)
        }
        changeCount += 1
    }

    func writeString(_ string: String) {
        storedString = string
        storedSnapshot = ClipboardSnapshot(
            items: [.init(representations: ["public.utf8-plain-text": Data(string.utf8)])]
        )
        changeCount += 1
    }
}
