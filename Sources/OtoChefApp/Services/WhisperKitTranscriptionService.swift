import Foundation
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
        let config = WhisperKitConfig(
            model: localModelFolder == nil ? settings.model : nil,
            downloadBase: modelBaseURL,
            modelFolder: localModelFolder?.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        let whisperKit = try await WhisperKit(config)
        let options = DecodingOptions(
            task: .transcribe,
            language: settings.language.isEmpty ? nil : settings.language,
            temperature: 0.0,
            wordTimestamps: false,
            concurrentWorkerCount: settings.cpuThreads,
            chunkingStrategy: settings.vadEnabled ? .vad : nil
        )
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        let segments = results
            .flatMap(\.segments)
            .enumerated()
            .map { index, segment in
                WhisperKitTranscriptSegment(
                    id: "seg-\(String(format: "%04d", index + 1))",
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: Self.sanitizeTranscriptText(segment.text)
                )
            }
            .filter { !$0.text.isEmpty }
        let data = try encoder.encode(WhisperKitTranscriptEnvelope(segments: segments))
        try data.write(to: outputURL, options: [.atomic])
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
