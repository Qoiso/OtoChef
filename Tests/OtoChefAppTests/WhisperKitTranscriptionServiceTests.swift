import XCTest
import CoreML
import WhisperKit
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

    func testVADChunkingUsesSameStrategyForEveryModelWhenEnabled() {
        for model in ASRSettings.whisperKitModelOptions {
            var settings = AppSettings.defaults.asr
            settings.model = model
            settings.vadEnabled = true

            XCTAssertTrue(WhisperKitTranscriptionService.usesVADChunking(settings: settings), model)
        }
    }

    func testVADChunkingIsDisabledWhenSettingIsOff() {
        var settings = AppSettings.defaults.asr
        settings.vadEnabled = false

        XCTAssertFalse(WhisperKitTranscriptionService.usesVADChunking(settings: settings))
    }

    func testLikelyFooterHallucinationIsFilteredFromSegments() {
        let segments = [
            WhisperKitTranscriptSegment(id: "seg-0001", start: 0, end: 2, text: "こんにちは"),
            WhisperKitTranscriptSegment(id: "seg-0002", start: 2, end: 4, text: "ご視聴ありがとうございました"),
            WhisperKitTranscriptSegment(id: "seg-0003", start: 4, end: 6, text: "またね")
        ]

        let filtered = WhisperKitTranscriptionService.filterLikelyHallucinations(segments)

        XCTAssertEqual(filtered.map(\.text), ["こんにちは", "またね"])
    }

    func testWhisperKitComputeOptionsMatchCLIStableDefaults() {
        let options = WhisperKitTranscriptionService.makeComputeOptions()

        XCTAssertEqual(options.audioEncoderCompute, .cpuAndNeuralEngine)
        XCTAssertEqual(options.textDecoderCompute, .cpuAndNeuralEngine)
    }

    func testWhisperKitConfigMatchesCLIStableLoadingDefaults() {
        let config = WhisperKitTranscriptionService.makeWhisperKitConfig(
            modelBaseURL: URL(fileURLWithPath: "/tmp/models", isDirectory: true),
            localModelFolder: URL(fileURLWithPath: "/tmp/models/openai_whisper-large-v3", isDirectory: true),
            settings: AppSettings.defaults.asr
        )

        XCTAssertEqual(config.modelFolder, "/tmp/models/openai_whisper-large-v3")
        XCTAssertEqual(config.prewarm, false)
        XCTAssertEqual(config.load, true)
        XCTAssertEqual(config.download, true)
        XCTAssertNil(config.voiceActivityDetector)
    }

    func testWhisperKitModelsUseTheSameConcurrencyCap() {
        for model in ASRSettings.whisperKitModelOptions {
            var settings = AppSettings.defaults.asr
            settings.model = model
            settings.cpuThreads = 8

            XCTAssertEqual(WhisperKitTranscriptionService.effectiveConcurrentWorkerCount(settings: settings), 4, model)
        }
    }

    func testDecodingOptionsUseStableWhisperKitThresholds() {
        var settings = AppSettings.defaults.asr
        settings.model = "openai_whisper-large-v3"
        settings.language = "ja"
        settings.cpuThreads = 8
        settings.vadEnabled = true

        let options = WhisperKitTranscriptionService.makeDecodingOptions(settings: settings)

        XCTAssertEqual(options.language, "ja")
        XCTAssertEqual(options.concurrentWorkerCount, 4)
        XCTAssertEqual(options.chunkingStrategy, .vad)
        XCTAssertNil(options.firstTokenLogProbThreshold)
    }

    func testSuspiciousTimingGapsAreDetected() {
        let segments = [
            WhisperKitTranscriptSegment(id: "seg-0001", start: 0, end: 5, text: "a"),
            WhisperKitTranscriptSegment(id: "seg-0002", start: 42, end: 50, text: "b")
        ]

        XCTAssertTrue(WhisperKitTranscriptionService.hasSuspiciousTimingGaps(segments))
    }

    func testSuspiciousTimingGapsDetectLeadingMissingAudio() {
        let segments = [
            WhisperKitTranscriptSegment(id: "seg-0001", start: 20.1, end: 26.3, text: "late start")
        ]

        XCTAssertTrue(WhisperKitTranscriptionService.hasSuspiciousTimingGaps(segments))
    }

    func testSequentialRetryIsUsedOnlyForSuspiciousParallelResults() {
        let segments = [
            WhisperKitTranscriptSegment(id: "seg-0001", start: 20.1, end: 26.3, text: "late start")
        ]

        XCTAssertTrue(WhisperKitTranscriptionService.shouldRetrySequentially(segments: segments, workerCount: 4))
        XCTAssertFalse(WhisperKitTranscriptionService.shouldRetrySequentially(segments: segments, workerCount: 1))
    }

    func testRetrySegmentsArePreferredWhenTheyRemoveSuspiciousGaps() {
        let primary = [
            WhisperKitTranscriptSegment(id: "seg-0001", start: 20.1, end: 26.3, text: "late start")
        ]
        let retry = [
            WhisperKitTranscriptSegment(id: "seg-0001", start: 0, end: 5, text: "start"),
            WhisperKitTranscriptSegment(id: "seg-0002", start: 5, end: 10, text: "next")
        ]

        XCTAssertEqual(
            WhisperKitTranscriptionService.preferredSegments(primary: primary, retry: retry),
            retry
        )
    }
}
