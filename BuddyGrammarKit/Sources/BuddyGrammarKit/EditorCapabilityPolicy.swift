import Foundation

public enum EditorFieldKind: String, Equatable, Sendable {
    case plainText
    case multiline
    case literal
    case search
    case emailAddress
    case url
    case personName
    case phoneNumber
    case number
    case decimal
    case dateTime
    case oneTimeCode
    case password
    case code
    case unknown
}

public enum EditorAutoCapitalizationMode: String, Equatable, Sendable {
    case none
    case words
    case sentences
    case allCharacters
}

public struct EditorFieldTraits: Equatable, Sendable {
    public let kind: EditorFieldKind
    public let isSecure: Bool
    public let suggestionsDisabled: Bool
    public let personalizedLearningDisabled: Bool
    public let autoCapitalization: EditorAutoCapitalizationMode

    public init(
        kind: EditorFieldKind = .plainText,
        isSecure: Bool = false,
        suggestionsDisabled: Bool = false,
        personalizedLearningDisabled: Bool = false,
        autoCapitalization: EditorAutoCapitalizationMode = .sentences
    ) {
        self.kind = kind
        self.isSecure = isSecure
        self.suggestionsDisabled = suggestionsDisabled
        self.personalizedLearningDisabled = personalizedLearningDisabled
        self.autoCapitalization = autoCapitalization
    }
}

public struct EditorCapabilityEnvironment: Equatable, Sendable {
    public let cloudTransportAvailable: Bool
    public let hasCloudProcessingConsent: Bool
    public let platformVoiceAvailable: Bool
    public let editorCanMoveCursor: Bool
    public let sharedContainerAvailable: Bool
    public let editorCanReadContext: Bool
    public let editorCanUseComposition: Bool

    public init(
        cloudTransportAvailable: Bool,
        hasCloudProcessingConsent: Bool,
        platformVoiceAvailable: Bool,
        editorCanMoveCursor: Bool,
        sharedContainerAvailable: Bool,
        editorCanReadContext: Bool = true,
        editorCanUseComposition: Bool = true
    ) {
        self.cloudTransportAvailable = cloudTransportAvailable
        self.hasCloudProcessingConsent = hasCloudProcessingConsent
        self.platformVoiceAvailable = platformVoiceAvailable
        self.editorCanMoveCursor = editorCanMoveCursor
        self.sharedContainerAvailable = sharedContainerAvailable
        self.editorCanReadContext = editorCanReadContext
        self.editorCanUseComposition = editorCanUseComposition
    }
}

public enum EditorCapabilityDenialReason: Equatable, Sendable {
    case sensitiveField
    case structuredField(EditorFieldKind)
    case codeField
    case suggestionsDisabled
    case personalizedLearningDisabled
    case cloudTransportUnavailable
    case cloudProcessingConsentRequired
    case platformVoiceUnavailable
    case cursorMovementUnavailable
    case sharedContainerUnavailable
    case contextReadUnavailable
    case compositionUnavailable
}

public enum EditorFeatureAccess: Equatable, Sendable {
    case allowed
    case denied(EditorCapabilityDenialReason)

    public var isAllowed: Bool {
        self == .allowed
    }

    public var denialReason: EditorCapabilityDenialReason? {
        guard case .denied(let reason) = self else { return nil }
        return reason
    }
}

public struct EditorCapabilities: Equatable, Sendable {
    public let fieldKind: EditorFieldKind
    public let presentationFieldKind: EditorFieldKind
    public let secure: Bool
    public let structured: Bool
    public let codeLike: Bool
    public let suggestions: EditorFeatureAccess
    public let personalizedLearning: EditorFeatureAccess
    public let automaticCorrection: EditorFeatureAccess
    public let swipeTyping: EditorFeatureAccess
    public let cursorMovement: EditorFeatureAccess
    public let cloudCorrection: EditorFeatureAccess
    public let cloudHandwriting: EditorFeatureAccess
    public let platformVoice: EditorFeatureAccess
    public let transcriptInsertion: EditorFeatureAccess
    public let readContext: EditorFeatureAccess
    public let useComposition: EditorFeatureAccess
    public let localHandwriting: EditorFeatureAccess
    public let literalTools: EditorFeatureAccess
    public let directLocalInsertion: EditorFeatureAccess
    public let clipboardInsertion: EditorFeatureAccess

    public init(
        fieldKind: EditorFieldKind,
        presentationFieldKind: EditorFieldKind,
        secure: Bool,
        structured: Bool,
        codeLike: Bool,
        suggestions: EditorFeatureAccess,
        personalizedLearning: EditorFeatureAccess,
        automaticCorrection: EditorFeatureAccess,
        swipeTyping: EditorFeatureAccess,
        cursorMovement: EditorFeatureAccess,
        cloudCorrection: EditorFeatureAccess,
        cloudHandwriting: EditorFeatureAccess,
        platformVoice: EditorFeatureAccess,
        transcriptInsertion: EditorFeatureAccess,
        readContext: EditorFeatureAccess,
        useComposition: EditorFeatureAccess,
        localHandwriting: EditorFeatureAccess,
        literalTools: EditorFeatureAccess,
        directLocalInsertion: EditorFeatureAccess,
        clipboardInsertion: EditorFeatureAccess
    ) {
        self.fieldKind = fieldKind
        self.presentationFieldKind = presentationFieldKind
        self.secure = secure
        self.structured = structured
        self.codeLike = codeLike
        self.suggestions = suggestions
        self.personalizedLearning = personalizedLearning
        self.automaticCorrection = automaticCorrection
        self.swipeTyping = swipeTyping
        self.cursorMovement = cursorMovement
        self.cloudCorrection = cloudCorrection
        self.cloudHandwriting = cloudHandwriting
        self.platformVoice = platformVoice
        self.transcriptInsertion = transcriptInsertion
        self.readContext = readContext
        self.useComposition = useComposition
        self.localHandwriting = localHandwriting
        self.literalTools = literalTools
        self.directLocalInsertion = directLocalInsertion
        self.clipboardInsertion = clipboardInsertion
    }
}

public enum EditorCapabilityPolicy {
    public static func evaluate(
        traits: EditorFieldTraits,
        environment: EditorCapabilityEnvironment
    ) -> EditorCapabilities {
        let fieldKind: EditorFieldKind = traits.isSecure
            ? .password
            : traits.kind
        let secure = traits.isSecure || fieldKind == .password || fieldKind == .oneTimeCode
        let structured = fieldKind.requiresLiteralInput
        let codeLike = fieldKind == .code
        let assistanceDisabled = traits.suggestionsDisabled || fieldKind == .literal
        let presentationFieldKind: EditorFieldKind = secure
            ? .password
            : assistanceDisabled && [.plainText, .multiline].contains(fieldKind)
                ? .literal
                : fieldKind
        let cursorMovement: EditorFeatureAccess = environment.editorCanMoveCursor
            ? .allowed
            : .denied(.cursorMovementUnavailable)

        if secure {
            return deniedTextCapabilities(
                reason: .sensitiveField,
                fieldKind: fieldKind,
                presentationFieldKind: presentationFieldKind,
                cursorMovement: cursorMovement
            )
        }
        if codeLike {
            return deniedTextCapabilities(
                reason: .codeField,
                fieldKind: fieldKind,
                presentationFieldKind: presentationFieldKind,
                cursorMovement: cursorMovement,
                literalTools: .allowed
            )
        }
        if structured {
            let deliberateInsertion: EditorFeatureAccess = assistanceDisabled
                ? .denied(.suggestionsDisabled)
                : .allowed
            return deniedTextCapabilities(
                reason: .structuredField(fieldKind),
                fieldKind: fieldKind,
                presentationFieldKind: presentationFieldKind,
                cursorMovement: cursorMovement,
                directLocalInsertion: deliberateInsertion,
                clipboardInsertion: deliberateInsertion
            )
        }

        let suggestions: EditorFeatureAccess = assistanceDisabled
            ? .denied(.suggestionsDisabled)
            : .allowed
        let learning: EditorFeatureAccess
        if !suggestions.isAllowed {
            learning = suggestions
        } else if fieldKind == .search {
            learning = .denied(.structuredField(.search))
        } else if traits.personalizedLearningDisabled {
            learning = .denied(.personalizedLearningDisabled)
        } else {
            learning = .allowed
        }

        let buddyText: EditorFeatureAccess
        if !suggestions.isAllowed {
            buddyText = suggestions
        } else if fieldKind == .search {
            buddyText = .denied(.structuredField(.search))
        } else if !environment.cloudTransportAvailable {
            buddyText = .denied(.cloudTransportUnavailable)
        } else if !environment.hasCloudProcessingConsent {
            buddyText = .denied(.cloudProcessingConsentRequired)
        } else {
            buddyText = .allowed
        }

        let platformVoice: EditorFeatureAccess = environment.platformVoiceAvailable
            ? .allowed
            : .denied(.platformVoiceUnavailable)

        let transcriptInsertion: EditorFeatureAccess
        if !suggestions.isAllowed {
            transcriptInsertion = suggestions
        } else if fieldKind == .search {
            transcriptInsertion = .denied(.structuredField(.search))
        } else if environment.sharedContainerAvailable {
            transcriptInsertion = .allowed
        } else {
            transcriptInsertion = .denied(.sharedContainerUnavailable)
        }

        let readContext: EditorFeatureAccess
        if !suggestions.isAllowed {
            readContext = suggestions
        } else if environment.editorCanReadContext {
            readContext = .allowed
        } else {
            readContext = .denied(.contextReadUnavailable)
        }
        let useComposition: EditorFeatureAccess
        if !suggestions.isAllowed {
            useComposition = suggestions
        } else if environment.editorCanUseComposition {
            useComposition = .allowed
        } else {
            useComposition = .denied(.compositionUnavailable)
        }
        let directLocalInsertion: EditorFeatureAccess = suggestions.isAllowed
            ? .allowed
            : suggestions

        return EditorCapabilities(
            fieldKind: fieldKind,
            presentationFieldKind: presentationFieldKind,
            secure: false,
            structured: false,
            codeLike: false,
            suggestions: suggestions,
            personalizedLearning: learning,
            automaticCorrection: suggestions,
            swipeTyping: suggestions,
            cursorMovement: cursorMovement,
            cloudCorrection: buddyText,
            cloudHandwriting: buddyText,
            platformVoice: platformVoice,
            transcriptInsertion: transcriptInsertion,
            readContext: readContext,
            useComposition: useComposition,
            localHandwriting: suggestions,
            literalTools: .allowed,
            directLocalInsertion: directLocalInsertion,
            clipboardInsertion: directLocalInsertion
        )
    }

    private static func deniedTextCapabilities(
        reason: EditorCapabilityDenialReason,
        fieldKind: EditorFieldKind,
        presentationFieldKind: EditorFieldKind,
        cursorMovement: EditorFeatureAccess,
        literalTools: EditorFeatureAccess? = nil,
        directLocalInsertion: EditorFeatureAccess? = nil,
        clipboardInsertion: EditorFeatureAccess? = nil
    ) -> EditorCapabilities {
        let denied = EditorFeatureAccess.denied(reason)
        return EditorCapabilities(
            fieldKind: fieldKind,
            presentationFieldKind: presentationFieldKind,
            secure: reason == .sensitiveField,
            structured: fieldKind.requiresLiteralInput,
            codeLike: fieldKind == .code,
            suggestions: denied,
            personalizedLearning: denied,
            automaticCorrection: denied,
            swipeTyping: denied,
            cursorMovement: cursorMovement,
            cloudCorrection: denied,
            cloudHandwriting: denied,
            platformVoice: denied,
            transcriptInsertion: denied,
            readContext: denied,
            useComposition: denied,
            localHandwriting: denied,
            literalTools: literalTools ?? denied,
            directLocalInsertion: directLocalInsertion ?? denied,
            clipboardInsertion: clipboardInsertion ?? denied
        )
    }
}

private extension EditorFieldKind {
    var requiresLiteralInput: Bool {
        switch self {
        case .emailAddress, .url, .personName, .phoneNumber, .number, .decimal,
             .dateTime:
            true
        case .plainText, .multiline, .literal, .search, .oneTimeCode, .password,
             .code, .unknown:
            false
        }
    }
}
