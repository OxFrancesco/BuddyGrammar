import XCTest
@testable import BuddyGrammarKit

final class EditorContextAccessGateTests: XCTestCase {
    func testDeniedCapabilityNeverInvokesContextSource() {
        var readCount = 0

        let value: String? = EditorContextAccessGate.read(
            capability: .denied(.sensitiveField)
        ) {
            readCount += 1
            return "secret"
        }

        XCTAssertNil(value)
        XCTAssertEqual(readCount, 0)
    }

    func testAllowedCapabilityReadsExactlyOnce() {
        var readCount = 0

        let value: String? = EditorContextAccessGate.read(capability: .allowed) {
            readCount += 1
            return "ordinary text"
        }

        XCTAssertEqual(value, "ordinary text")
        XCTAssertEqual(readCount, 1)
    }

    func testSensitiveStructuredCodeAndNoSuggestionPoliciesPerformZeroReads() {
        let traits: [EditorFieldTraits] = [
            EditorFieldTraits(kind: .password, isSecure: true),
            EditorFieldTraits(kind: .oneTimeCode),
            EditorFieldTraits(kind: .code),
            EditorFieldTraits(kind: .emailAddress),
            EditorFieldTraits(kind: .plainText, suggestionsDisabled: true),
        ]
        let environment = EditorCapabilityEnvironment(
            cloudTransportAvailable: true,
            hasCloudProcessingConsent: true,
            platformVoiceAvailable: true,
            editorCanMoveCursor: true,
            sharedContainerAvailable: true
        )

        for fieldTraits in traits {
            var spyReadCount = 0
            let capabilities = EditorCapabilityPolicy.evaluate(
                traits: fieldTraits,
                environment: environment
            )

            let context: String? = EditorContextAccessGate.read(
                capability: capabilities.readContext
            ) {
                spyReadCount += 1
                return "must never be observed"
            }

            XCTAssertNil(context, "Unexpected context for \(fieldTraits.kind)")
            XCTAssertEqual(spyReadCount, 0, "Unexpected read for \(fieldTraits.kind)")
        }
    }
}
