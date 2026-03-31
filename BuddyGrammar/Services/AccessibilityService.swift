import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AccessibilityService {
    func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func readSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: AnyObject?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusedError == .success, let element = focusedObject else { return nil }
        let focusedElement = element as! AXUIElement

        if let selected = copyString(attribute: kAXSelectedTextAttribute, from: focusedElement),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }

        guard let value = copyString(attribute: kAXValueAttribute, from: focusedElement),
              let rangeValue = copyRange(attribute: kAXSelectedTextRangeAttribute, from: focusedElement)
        else {
            return nil
        }

        let nsRange = NSRange(location: rangeValue.location, length: rangeValue.length)
        guard nsRange.location != NSNotFound,
              nsRange.length > 0,
              let range = Range(nsRange, in: value)
        else {
            return nil
        }
        return String(value[range])
    }

    private func copyString(attribute: String, from element: AXUIElement) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private func copyRange(attribute: String, from element: AXUIElement) -> CFRange? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange
        else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }
}
