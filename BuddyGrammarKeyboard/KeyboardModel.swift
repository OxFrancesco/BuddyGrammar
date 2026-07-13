import BuddyGrammarKit
import Foundation
import Observation

enum KeyboardLayoutMode: Equatable {
    case letters
    case symbols
}

enum KeyboardShiftState: Equatable {
    case lowercase
    case uppercase
}

enum KeyboardStatus: Equatable {
    case ready
    case correcting
    case corrected
    case transcriptInserted
    case fullAccessRequired
    case cloudConsentRequired
    case noText
    case noPendingTranscript
    case staleContext
    case error(String)

    var message: String {
        switch self {
        case .ready:
            "Select text or place the cursor after a sentence, then tap ★."
        case .correcting:
            "Correcting…"
        case .corrected:
            "Correction applied."
        case .transcriptInserted:
            "Dictation inserted."
        case .fullAccessRequired:
            "Typing works. Enable Full Access for ★ and dictation."
        case .cloudConsentRequired:
            "Accept cloud processing in the BuddyGrammar app to use ★."
        case .noText:
            "Select text or type a sentence first."
        case .noPendingTranscript:
            "No dictation is waiting. Record one in BuddyGrammar first."
        case .staleContext:
            "The text changed, so the correction was not applied."
        case .error(let message):
            message
        }
    }

    var isError: Bool {
        switch self {
        case .fullAccessRequired, .cloudConsentRequired,
             .noText, .noPendingTranscript, .staleContext, .error:
            true
        case .ready, .correcting, .corrected, .transcriptInserted:
            false
        }
    }
}

enum DocumentCorrectionTarget: Equatable, Sendable {
    case selection
    case precedingSentence
}

struct DocumentCorrectionSnapshot: Equatable, Sendable {
    let documentIdentifier: UUID
    let generation: UInt64
    let contextBeforeInput: String?
    let selectedText: String?
    let contextAfterInput: String?
    let target: DocumentCorrectionTarget
    let candidate: TextCorrectionCandidate
}

@MainActor
protocol KeyboardModelDelegate: AnyObject {
    var keyboardHasFullAccess: Bool { get }

    func insertText(_ text: String)
    func deleteBackward()
    func captureCorrectionSnapshot() -> DocumentCorrectionSnapshot?
    func applyCorrection(_ replacement: String, to snapshot: DocumentCorrectionSnapshot) -> Bool
}

@MainActor
@Observable
final class KeyboardModel {
    var layoutMode: KeyboardLayoutMode = .letters
    var shiftState: KeyboardShiftState = .uppercase
    private(set) var status: KeyboardStatus = .fullAccessRequired
    private(set) var hasFullAccess = false

    @ObservationIgnored private weak var delegate: KeyboardModelDelegate?
    @ObservationIgnored private let correctionClient: OpenRouterCorrectionClient
    @ObservationIgnored private let preferences: SharedPreferences?
    @ObservationIgnored private var correctionTask: Task<Void, Never>?
    @ObservationIgnored private var correctionRequestID: UUID?
    @ObservationIgnored private var baselineStatus: KeyboardStatus = .fullAccessRequired

    init(
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient(),
        preferences: SharedPreferences? = SharedPreferences()
    ) {
        self.correctionClient = correctionClient
        self.preferences = preferences
    }

    func connect(delegate: KeyboardModelDelegate) {
        self.delegate = delegate
        refreshAvailability()
    }

    func refreshAvailability() {
        hasFullAccess = delegate?.keyboardHasFullAccess ?? false

        guard hasFullAccess else {
            cancelCorrection()
            baselineStatus = .fullAccessRequired
            status = baselineStatus
            return
        }

        let shouldPreserveCorrectionStatus = correctionTask != nil
        baselineStatus = availabilityStatus()
        if !shouldPreserveCorrectionStatus {
            status = baselineStatus
        }
    }

    func insertCharacter(_ character: String) {
        cancelCorrectionForLocalEdit()
        let output = shiftState == .uppercase && layoutMode == .letters
            ? character.uppercased()
            : character
        delegate?.insertText(output)

        if layoutMode == .letters, shiftState == .uppercase {
            shiftState = .lowercase
        }
    }

    func insertSpace() {
        cancelCorrectionForLocalEdit()
        delegate?.insertText(" ")
    }

    func insertReturn() {
        cancelCorrectionForLocalEdit()
        delegate?.insertText("\n")
        if layoutMode == .letters {
            shiftState = .uppercase
        }
    }

    func deleteBackward() {
        cancelCorrectionForLocalEdit()
        delegate?.deleteBackward()
    }

    func toggleShift() {
        shiftState = shiftState == .lowercase ? .uppercase : .lowercase
    }

    func toggleLayout() {
        cancelCorrectionForLocalEdit()
        layoutMode = layoutMode == .letters ? .symbols : .letters
    }

    func documentContextDidChange() {
        guard correctionTask != nil else { return }
        cancelCorrection()
        status = baselineStatus
    }

    func deactivate() {
        cancelCorrection()
        status = baselineStatus
    }

    func correctCurrentText() {
        cancelCorrection()
        refreshAvailability()

        guard hasFullAccess else {
            status = .fullAccessRequired
            return
        }

        let settings = preferences?.loadSettings() ?? .default
        guard settings.hasAcceptedCloudProcessing else {
            status = .cloudConsentRequired
            return
        }

        guard let snapshot = delegate?.captureCorrectionSnapshot() else {
            status = .noText
            return
        }

        guard let clientID = preferences?.installationIdentifier() else {
            status = .error("BuddyGrammar could not open its shared container.")
            return
        }

        let requestID = UUID()
        correctionRequestID = requestID
        status = .correcting

        correctionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let corrected = try await correctionClient.correct(
                    text: snapshot.candidate.requestText,
                    clientID: clientID,
                    modelID: settings.openRouterModelID,
                    instruction: settings.correctionInstruction
                )
                try Task.checkCancellation()
                guard correctionRequestID == requestID else { return }

                let replacement = snapshot.candidate.replacement(with: corrected)
                let didApply = delegate?.applyCorrection(replacement, to: snapshot) ?? false
                correctionTask = nil
                correctionRequestID = nil
                status = didApply ? .corrected : .staleContext
            } catch is CancellationError {
                // Cancellation is expected whenever the document changes.
            } catch {
                guard correctionRequestID == requestID else { return }
                correctionTask = nil
                correctionRequestID = nil
                status = .error(error.localizedDescription)
            }
        }
    }

    func insertPendingTranscript() {
        cancelCorrectionForLocalEdit()
        refreshAvailability()

        guard hasFullAccess else {
            status = .fullAccessRequired
            return
        }

        guard let preferences else {
            status = .error("BuddyGrammar could not open its shared container.")
            return
        }

        guard let transcript = preferences.loadPendingTranscript(),
              !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .noPendingTranscript
            return
        }

        delegate?.insertText(transcript.text)
        preferences.clearPendingTranscript()
        status = .transcriptInserted
    }

    private func cancelCorrectionForLocalEdit() {
        cancelCorrection()
        status = baselineStatus
    }

    private func cancelCorrection() {
        correctionTask?.cancel()
        correctionTask = nil
        correctionRequestID = nil
    }

    private func availabilityStatus() -> KeyboardStatus {
        let fullAccess = delegate?.keyboardHasFullAccess ?? false
        hasFullAccess = fullAccess
        guard fullAccess else { return .fullAccessRequired }

        let settings = preferences?.loadSettings() ?? .default
        guard settings.hasAcceptedCloudProcessing else {
            return .cloudConsentRequired
        }

        return .ready
    }
}
