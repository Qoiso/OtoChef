import Foundation

struct AppSettings: Codable, Equatable {
    var asr: ASRSettings
    var translation: TranslationSettings
    var conda: CondaSettings
    var tools: ToolSettings
    var video: VideoSettings

    static let defaults = AppSettings(
        asr: ASRSettings(
            backend: .fasterWhisper,
            model: "Systran/faster-whisper-large-v3",
            device: "auto",
            computeType: "auto",
            language: "ja",
            vadEnabled: true,
            beamSize: 5
        ),
        translation: TranslationSettings(
            backend: .api,
            endpoint: "http://localhost:11434/v1",
            model: "qwen2.5:7b",
            prompt: "Translate each Japanese subtitle segment into natural Simplified Chinese. Preserve IDs.",
            timeoutSeconds: 120,
            retryLimit: 2
        ),
        conda: CondaSettings(executablePath: "/opt/homebrew/bin/conda", environmentName: "otochef"),
        tools: ToolSettings(ffmpegPath: "/opt/homebrew/bin/ffmpeg"),
        video: VideoSettings(width: 1920, height: 1080, imageFit: .contain, backgroundColor: "black")
    )
}

enum ASRBackend: String, Codable, Equatable {
    case fasterWhisper
}

struct ASRSettings: Codable, Equatable {
    var backend: ASRBackend
    var model: String
    var device: String
    var computeType: String
    var language: String
    var vadEnabled: Bool
    var beamSize: Int
}

enum TranslationBackend: String, Codable, Equatable {
    case local
    case api
}

struct TranslationSettings: Codable, Equatable {
    var backend: TranslationBackend
    var endpoint: String
    var model: String
    var prompt: String
    var timeoutSeconds: Int
    var retryLimit: Int
}

struct CondaSettings: Codable, Equatable {
    var executablePath: String
    var environmentName: String
}

struct ToolSettings: Codable, Equatable {
    var ffmpegPath: String
}

enum ImageFit: String, Codable, Equatable {
    case contain
    case cover
}

struct VideoSettings: Codable, Equatable {
    var width: Int
    var height: Int
    var imageFit: ImageFit
    var backgroundColor: String
}
