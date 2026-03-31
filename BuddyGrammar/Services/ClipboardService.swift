import AppKit
import Foundation

struct ClipboardSnapshot: Equatable {
    struct Item: Equatable {
        var representations: [String: Data]
    }

    var items: [Item]
}

protocol PasteboardControlling: AnyObject {
    var changeCount: Int { get }
    func readString() -> String?
    func snapshot() -> ClipboardSnapshot
    func restore(snapshot: ClipboardSnapshot)
    func writeString(_ string: String)
}

final class SystemPasteboardController: PasteboardControlling {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func snapshot() -> ClipboardSnapshot {
        let items: [ClipboardSnapshot.Item] = pasteboard.pasteboardItems?.map { item in
            var representations: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                representations[type.rawValue] = data
            }
            return ClipboardSnapshot.Item(representations: representations)
        } ?? []
        return ClipboardSnapshot(items: items)
    }

    func restore(snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        for item in snapshot.items {
            let pbItem = NSPasteboardItem()
            for (typeIdentifier, data) in item.representations {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
            }
            pasteboard.writeObjects([pbItem])
        }
    }

    func writeString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

final class ClipboardService {
    private let pasteboard: PasteboardControlling

    init(pasteboard: PasteboardControlling = SystemPasteboardController()) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> ClipboardSnapshot {
        pasteboard.snapshot()
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.restore(snapshot: snapshot)
    }

    func readString() -> String? {
        pasteboard.readString()
    }

    func writeString(_ string: String) {
        pasteboard.writeString(string)
    }
}
