import Foundation

/// Converts user-perceived cursor steps into the UTF-16 offsets consumed by
/// UIKit text-position APIs. Context remains bounded and process-local.
public enum KeyboardCursorOffsetPolicy {
    public static func utf16Offset(
        forGraphemeDelta delta: Int,
        contextBeforeInput: String?,
        contextAfterInput: String?,
        maximumGraphemes: Int = 64
    ) -> Int {
        guard delta != 0 else { return 0 }
        let limit = max(1, maximumGraphemes)
        let count = Int(min(delta.magnitude, UInt(limit)))
        if delta < 0 {
            guard let contextBeforeInput else { return delta }
            let suffix = String(contextBeforeInput.suffix(count))
            return -suffix.utf16.count
        }
        guard let contextAfterInput else { return delta }
        let prefix = String(contextAfterInput.prefix(count))
        return prefix.utf16.count
    }
}
