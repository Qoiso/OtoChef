import XCTest
@testable import OtoChefApp

final class WhisperKitTranscriptionServiceTests: XCTestCase {
    func testSanitizeTranscriptTextRemovesWhisperControlTokens() {
        let text = "<|startoftranscript|><|ja|><|transcribe|><|0.00|>こんにちは<|1.25|><|endoftext|>"

        let sanitized = WhisperKitTranscriptionService.sanitizeTranscriptText(text)

        XCTAssertEqual(sanitized, "こんにちは")
    }

    func testTranscriptEnvelopeEncodesSegmentsForPythonWorker() throws {
        let envelope = WhisperKitTranscriptEnvelope(
            segments: [
                WhisperKitTranscriptSegment(id: "seg-0001", start: 0, end: 1.25, text: "こんにちは"),
                WhisperKitTranscriptSegment(id: "seg-0002", start: 1.25, end: 2.5, text: "世界")
            ]
        )

        let data = try JSONEncoder().encode(envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"id\":\"seg-0001\""))
        XCTAssertTrue(json.contains("\"text\":\"こんにちは\""))
    }
}
