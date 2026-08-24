import XCTest
@testable import BuddyGrammarKit

final class EditorCapabilityPolicyTests: XCTestCase {
    func testPlainTextCloudReadyMatchesSharedContract() {
        let capabilities = evaluate()

        XCTAssertEqual(capabilities.suggestions, .allowed)
        XCTAssertEqual(capabilities.personalizedLearning, .allowed)
        XCTAssertEqual(capabilities.automaticCorrection, .allowed)
        XCTAssertEqual(capabilities.swipeTyping, .allowed)
        XCTAssertEqual(capabilities.cursorMovement, .allowed)
        XCTAssertEqual(capabilities.cloudCorrection, .allowed)
        XCTAssertEqual(capabilities.cloudHandwriting, .allowed)
        XCTAssertEqual(capabilities.platformVoice, .allowed)
        XCTAssertEqual(capabilities.transcriptInsertion, .allowed)
        XCTAssertEqual(capabilities.readContext, .allowed)
        XCTAssertEqual(capabilities.useComposition, .allowed)
        XCTAssertEqual(capabilities.presentationFieldKind, .plainText)
    }

    func testSecureAndOneTimeCodeFieldsDenyTextToolsButNotCursorPrimitive() {
        for traits in [
            EditorFieldTraits(kind: .password, isSecure: true),
            EditorFieldTraits(kind: .plainText, isSecure: true),
            EditorFieldTraits(kind: .oneTimeCode),
        ] {
            let capabilities = evaluate(traits: traits)

            assertTextTools(
                capabilities,
                deniedBy: .sensitiveField,
                file: #filePath,
                line: #line
            )
            XCTAssertEqual(capabilities.cursorMovement, .allowed)
            XCTAssertEqual(
                capabilities.clipboardInsertion,
                .denied(.sensitiveField)
            )
        }
    }

    func testStructuredAndCodeFieldsMatchSharedContract() {
        let structuredKinds: [EditorFieldKind] = [
            .emailAddress, .url, .personName, .phoneNumber, .number, .decimal,
            .dateTime,
        ]

        for kind in structuredKinds {
            let capabilities = evaluate(traits: EditorFieldTraits(kind: kind))
            assertTextTools(
                capabilities,
                deniedBy: .structuredField(kind),
                file: #filePath,
                line: #line
            )
            XCTAssertEqual(capabilities.cursorMovement, .allowed)
            XCTAssertEqual(capabilities.directLocalInsertion, .allowed)
            XCTAssertEqual(capabilities.clipboardInsertion, .allowed)
        }

        let code = evaluate(traits: EditorFieldTraits(kind: .code))
        assertTextTools(code, deniedBy: .codeField)
        XCTAssertEqual(code.cursorMovement, .allowed)
        XCTAssertEqual(code.literalTools, .allowed)
        XCTAssertEqual(code.clipboardInsertion, .denied(.codeField))
    }

    func testSearchIsLocalOnlyAndKeepsPlatformVoice() {
        let capabilities = evaluate(traits: EditorFieldTraits(kind: .search))

        XCTAssertEqual(capabilities.suggestions, .allowed)
        XCTAssertEqual(capabilities.automaticCorrection, .allowed)
        XCTAssertEqual(capabilities.swipeTyping, .allowed)
        XCTAssertEqual(
            capabilities.personalizedLearning,
            .denied(.structuredField(.search))
        )
        XCTAssertEqual(
            capabilities.cloudCorrection,
            .denied(.structuredField(.search))
        )
        XCTAssertEqual(
            capabilities.cloudHandwriting,
            .denied(.structuredField(.search))
        )
        XCTAssertEqual(capabilities.platformVoice, .allowed)
        XCTAssertEqual(capabilities.readContext, .allowed)
        XCTAssertEqual(capabilities.useComposition, .allowed)
        XCTAssertEqual(
            capabilities.transcriptInsertion,
            .denied(.structuredField(.search))
        )
    }

    func testStructuredClipboardIsDeliberateUnlessTheEditorDisablesAssistance() {
        let email = evaluate(traits: EditorFieldTraits(kind: .emailAddress))
        XCTAssertEqual(email.clipboardInsertion, .allowed)

        let editorDisabled = evaluate(
            traits: EditorFieldTraits(
                kind: .emailAddress,
                suggestionsDisabled: true
            )
        )
        XCTAssertEqual(
            editorDisabled.clipboardInsertion,
            .denied(.suggestionsDisabled)
        )
    }

    func testNoSuggestionsBlocksPredictionSwipeAndBuddyButNotPlatformVoice() {
        let capabilities = evaluate(
            traits: EditorFieldTraits(suggestionsDisabled: true)
        )

        XCTAssertEqual(capabilities.suggestions, .denied(.suggestionsDisabled))
        XCTAssertEqual(capabilities.presentationFieldKind, .literal)
        XCTAssertEqual(
            capabilities.personalizedLearning,
            .denied(.suggestionsDisabled)
        )
        XCTAssertEqual(
            capabilities.automaticCorrection,
            .denied(.suggestionsDisabled)
        )
        XCTAssertEqual(capabilities.swipeTyping, .denied(.suggestionsDisabled))
        XCTAssertEqual(
            capabilities.cloudCorrection,
            .denied(.suggestionsDisabled)
        )
        XCTAssertEqual(
            capabilities.cloudHandwriting,
            .denied(.suggestionsDisabled)
        )
        XCTAssertEqual(capabilities.platformVoice, .allowed)
        XCTAssertEqual(
            capabilities.transcriptInsertion,
            .denied(.suggestionsDisabled)
        )
        XCTAssertEqual(capabilities.readContext, .denied(.suggestionsDisabled))
        XCTAssertEqual(capabilities.useComposition, .denied(.suggestionsDisabled))
        XCTAssertEqual(
            capabilities.clipboardInsertion,
            .denied(.suggestionsDisabled)
        )
    }

    func testPersonalizedLearningFlagOnlyDisablesProfileWrites() {
        let capabilities = evaluate(
            traits: EditorFieldTraits(personalizedLearningDisabled: true)
        )

        XCTAssertEqual(capabilities.suggestions, .allowed)
        XCTAssertEqual(capabilities.automaticCorrection, .allowed)
        XCTAssertEqual(capabilities.swipeTyping, .allowed)
        XCTAssertEqual(
            capabilities.personalizedLearning,
            .denied(.personalizedLearningDisabled)
        )
        XCTAssertEqual(capabilities.cloudCorrection, .allowed)
        XCTAssertEqual(capabilities.platformVoice, .allowed)
        XCTAssertEqual(capabilities.readContext, .allowed)
    }

    func testCloudTransportAndConsentDoNotAffectLocalOrPlatformVoice() {
        let withoutTransport = evaluate(
            environment: EditorCapabilityEnvironment(
                cloudTransportAvailable: false,
                hasCloudProcessingConsent: true,
                platformVoiceAvailable: false,
                editorCanMoveCursor: true,
                sharedContainerAvailable: false
            )
        )

        XCTAssertEqual(withoutTransport.suggestions, .allowed)
        XCTAssertEqual(withoutTransport.swipeTyping, .allowed)
        XCTAssertEqual(
            withoutTransport.cloudCorrection,
            .denied(.cloudTransportUnavailable)
        )
        XCTAssertEqual(
            withoutTransport.platformVoice,
            .denied(.platformVoiceUnavailable)
        )
        XCTAssertEqual(
            withoutTransport.transcriptInsertion,
            .denied(.sharedContainerUnavailable)
        )

        let withoutConsent = evaluate(
            environment: EditorCapabilityEnvironment(
                cloudTransportAvailable: true,
                hasCloudProcessingConsent: false,
                platformVoiceAvailable: true,
                editorCanMoveCursor: true,
                sharedContainerAvailable: true
            )
        )
        XCTAssertEqual(
            withoutConsent.cloudCorrection,
            .denied(.cloudProcessingConsentRequired)
        )
        XCTAssertEqual(
            withoutConsent.cloudHandwriting,
            .denied(.cloudProcessingConsentRequired)
        )
        XCTAssertEqual(withoutConsent.platformVoice, .allowed)
        XCTAssertEqual(withoutConsent.transcriptInsertion, .allowed)
    }

    func testCursorCapabilityReflectsEditorPrimitiveIndependently() {
        let capabilities = evaluate(
            environment: EditorCapabilityEnvironment(
                cloudTransportAvailable: true,
                hasCloudProcessingConsent: true,
                platformVoiceAvailable: true,
                editorCanMoveCursor: false,
                sharedContainerAvailable: true
            )
        )

        XCTAssertEqual(
            capabilities.cursorMovement,
            .denied(.cursorMovementUnavailable)
        )
        XCTAssertEqual(capabilities.suggestions, .allowed)
        XCTAssertEqual(capabilities.cloudCorrection, .allowed)
    }

    func testContextAndCompositionPrimitivesDegradeIndependently() {
        let capabilities = evaluate(
            environment: EditorCapabilityEnvironment(
                cloudTransportAvailable: true,
                hasCloudProcessingConsent: true,
                platformVoiceAvailable: true,
                editorCanMoveCursor: true,
                sharedContainerAvailable: true,
                editorCanReadContext: false,
                editorCanUseComposition: false
            )
        )

        XCTAssertEqual(capabilities.suggestions, .allowed)
        XCTAssertEqual(capabilities.readContext, .denied(.contextReadUnavailable))
        XCTAssertEqual(capabilities.useComposition, .denied(.compositionUnavailable))
    }

    private func evaluate(
        traits: EditorFieldTraits = EditorFieldTraits(),
        environment: EditorCapabilityEnvironment = EditorCapabilityEnvironment(
            cloudTransportAvailable: true,
            hasCloudProcessingConsent: true,
            platformVoiceAvailable: true,
            editorCanMoveCursor: true,
            sharedContainerAvailable: true
        )
    ) -> EditorCapabilities {
        EditorCapabilityPolicy.evaluate(traits: traits, environment: environment)
    }

    private func assertTextTools(
        _ capabilities: EditorCapabilities,
        deniedBy reason: EditorCapabilityDenialReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let denial = EditorFeatureAccess.denied(reason)
        XCTAssertEqual(capabilities.suggestions, denial, file: file, line: line)
        XCTAssertEqual(capabilities.personalizedLearning, denial, file: file, line: line)
        XCTAssertEqual(capabilities.automaticCorrection, denial, file: file, line: line)
        XCTAssertEqual(capabilities.swipeTyping, denial, file: file, line: line)
        XCTAssertEqual(capabilities.cloudCorrection, denial, file: file, line: line)
        XCTAssertEqual(capabilities.cloudHandwriting, denial, file: file, line: line)
        XCTAssertEqual(capabilities.platformVoice, denial, file: file, line: line)
        XCTAssertEqual(capabilities.transcriptInsertion, denial, file: file, line: line)
        XCTAssertEqual(capabilities.readContext, denial, file: file, line: line)
        XCTAssertEqual(capabilities.useComposition, denial, file: file, line: line)
        XCTAssertEqual(capabilities.localHandwriting, denial, file: file, line: line)
    }
}
