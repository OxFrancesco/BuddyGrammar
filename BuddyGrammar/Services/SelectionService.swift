import Foundation

@MainActor
final class SelectionService {
    private let accessibilityService: AccessibilityService
    private let clipboardService: ClipboardService
    private let eventSimulationService: EventSimulationService

    init(
        accessibilityService: AccessibilityService,
        clipboardService: ClipboardService,
        eventSimulationService: EventSimulationService
    ) {
        self.accessibilityService = accessibilityService
        self.clipboardService = clipboardService
        self.eventSimulationService = eventSimulationService
    }

    func captureSelectedText() async throws -> String {
        if let selected = accessibilityService.readSelectedText(),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }

        let snapshot = clipboardService.snapshot()
        let previousChangeCount = clipboardService.changeCount
        try eventSimulationService.simulateCopy()

        let timeout = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < timeout {
            if clipboardService.changeCount != previousChangeCount {
                let captured = clipboardService.readString() ?? ""
                clipboardService.restore(snapshot)
                guard !captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RewriteFailure.emptySelection
                }
                return captured
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        clipboardService.restore(snapshot)
        throw RewriteFailure.selectionUnavailable
    }
}
