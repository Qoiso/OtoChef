import Foundation
import CoreML
import WhisperKit

protocol NativeTranscriptionService {
    func transcribe(audioURL: URL, settings: ASRSettings, outputURL: URL, projectRoot: URL) async throws
}

struct WhisperKitTranscriptEnvelope: Codable, Equatable {
    var segments: [WhisperKitTranscriptSegment]
}

struct WhisperKitTranscriptSegment: Codable, Equatable {
    var id: String
    var start: Double
    var end: Double
    var text: String
}

struct WhisperKitTranscriptionService: NativeTranscriptionService {
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func transcribe(audioURL: URL, settings: ASRSettings, outputURL: URL, projectRoot: URL) async throws {
        let modelBaseURL = WhisperKitModelPathResolver(projectRoot: projectRoot)
            .resolveModelBaseURL(settings.modelFolder)
        try fileManager.createDirectory(at: modelBaseURL, withIntermediateDirectories: true)

        let localModelFolder = resolveLocalModelFolder(modelBaseURL: modelBaseURL, model: settings.model)
        let config = Self.makeWhisperKitConfig(
            modelBaseURL: modelBaseURL,
            localModelFolder: localModelFolder,
            settings: settings
        )
        let whisperKit = try await WhisperKit(config)
        let options = Self.makeDecodingOptions(settings: settings)
        let primarySegments = try await Self.transcribeSegments(
            audioPath: audioURL.path,
            whisperKit: whisperKit,
            options: options
        )
        let segments: [WhisperKitTranscriptSegment]
        if Self.shouldRetrySequentially(
            segments: primarySegments,
            workerCount: options.concurrentWorkerCount
        ) {
            let retryOptions = Self.makeDecodingOptions(settings: settings, concurrentWorkerCount: 1)
            let retrySegments = try await Self.transcribeSegments(
                audioPath: audioURL.path,
                whisperKit: whisperKit,
                options: retryOptions
            )
            segments = Self.preferredSegments(primary: primarySegments, retry: retrySegments)
        } else {
            segments = primarySegments
        }
        let data = try encoder.encode(WhisperKitTranscriptEnvelope(segments: segments))
        try data.write(to: outputURL, options: [.atomic])
    }

    static func usesVADChunking(settings: ASRSettings) -> Bool {
        settings.vadEnabled
    }

    static func effectiveConcurrentWorkerCount(settings: ASRSettings) -> Int {
        let requested = max(1, settings.cpuThreads)
        return min(requested, ASRSettings.maxWhisperKitConcurrentSegments)
    }

    static func makeDecodingOptions(
        settings: ASRSettings,
        concurrentWorkerCount: Int? = nil
    ) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: settings.language.isEmpty ? nil : settings.language,
            temperature: 0.0,
            usePrefillPrompt: true,
            wordTimestamps: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: concurrentWorkerCount ?? Self.effectiveConcurrentWorkerCount(settings: settings),
            chunkingStrategy: Self.usesVADChunking(settings: settings) ? .vad : nil
        )
    }

    static func transcribeSegments(
        audioPath: String,
        whisperKit: WhisperKit,
        options: DecodingOptions
    ) async throws -> [WhisperKitTranscriptSegment] {
        let results = await whisperKit.transcribeWithResults(
            audioPaths: [audioPath],
            decodeOptions: options
        )
        let partialResults = try results.first?.get() ?? []
        let mergedResult = TranscriptionUtilities.mergeTranscriptionResults(partialResults)
        let recognizedSegments = mergedResult.segments
            .map { segment in
                WhisperKitTranscriptSegment(
                    id: "",
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: Self.sanitizeTranscriptText(segment.text)
                )
            }
            .filter { !$0.text.isEmpty }

        return Self.filterLikelyHallucinations(recognizedSegments)
            .enumerated()
            .map { index, segment in
                WhisperKitTranscriptSegment(
                    id: "seg-\(String(format: "%04d", index + 1))",
                    start: segment.start,
                    end: segment.end,
                    text: segment.text
                )
            }
    }

    static func makeComputeOptions() -> ModelComputeOptions {
        ModelComputeOptions(
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
    }

    static func makeWhisperKitConfig(
        modelBaseURL: URL,
        localModelFolder: URL?,
        settings: ASRSettings
    ) -> WhisperKitConfig {
        WhisperKitConfig(
            model: localModelFolder == nil ? settings.model : nil,
            downloadBase: modelBaseURL,
            modelFolder: localModelFolder?.path,
            computeOptions: Self.makeComputeOptions(),
            verbose: false,
            prewarm: false,
            load: true,
            download: true
        )
    }

    static func filterLikelyHallucinations(_ segments: [WhisperKitTranscriptSegment]) -> [WhisperKitTranscriptSegment] {
        segments.filter { !isLikelyFooterHallucination($0.text) }
    }

    static func hasSuspiciousTimingGaps(
        _ segments: [WhisperKitTranscriptSegment],
        maxLeadingGap: Double = 10,
        maxExpectedGap: Double = 20
    ) -> Bool {
        guard let firstSegment = segments.first else {
            return false
        }
        if firstSegment.start > maxLeadingGap {
            return true
        }
        guard segments.count > 1 else {
            return false
        }
        return zip(segments, segments.dropFirst()).contains { previous, current in
            current.start - previous.end > maxExpectedGap
        }
    }

    static func shouldRetrySequentially(
        segments: [WhisperKitTranscriptSegment],
        workerCount: Int
    ) -> Bool {
        workerCount > 1 && Self.hasSuspiciousTimingGaps(segments)
    }

    static func preferredSegments(
        primary: [WhisperKitTranscriptSegment],
        retry: [WhisperKitTranscriptSegment]
    ) -> [WhisperKitTranscriptSegment] {
        if Self.hasSuspiciousTimingGaps(primary) && !Self.hasSuspiciousTimingGaps(retry) {
            return retry
        }
        if retry.count > primary.count * 2 {
            return retry
        }
        return primary
    }

    private static func isLikelyFooterHallucination(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "ご視聴ありがとうございました"
    }

    private func resolveLocalModelFolder(modelBaseURL: URL, model: String) -> URL? {
        let direct = URL(fileURLWithPath: model.expandingTildeInPath, isDirectory: true)
        if containsWhisperKitModelFiles(direct) {
            return direct
        }

        let candidates = [
            modelBaseURL,
            modelBaseURL.appendingPathComponent(model, isDirectory: true),
            modelBaseURL.appendingPathComponent("openai_whisper-\(model)", isDirectory: true)
        ]
        return candidates.first(where: containsWhisperKitModelFiles)
    }

    private func containsWhisperKitModelFiles(_ folder: URL) -> Bool {
        let requiredNames = ["AudioEncoder", "TextDecoder", "MelSpectrogram"]
        return requiredNames.allSatisfy { name in
            fileManager.fileExists(atPath: folder.appendingPathComponent("\(name).mlmodelc").path)
                || fileManager.fileExists(atPath: folder.appendingPathComponent("\(name).mlpackage").path)
        }
    }

    static func sanitizeTranscriptText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<\|[^|]+?\|>"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WhisperKitModelPathResolver {
    var projectRoot: URL

    func resolveModelBaseURL(_ modelFolder: String) -> URL {
        let expandedPath = modelFolder.expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath, isDirectory: true)
        }
        return projectRoot.appendingPathComponent(expandedPath, isDirectory: true)
    }
}

extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
