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
            device: "cpu",
            computeType: "int8",
            language: "ja",
            vadEnabled: true,
            beamSize: 1,
            cpuThreads: 8
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
        tools: ToolSettings(ffmpegPath: ToolSettings.defaultFFmpegPath()),
        video: VideoSettings(width: 1920, height: 1080, imageFit: .contain, backgroundColor: "black")
    )

    func resolvingAvailableToolDefaults(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> AppSettings {
        var settings = self
        if settings.tools.ffmpegPath == ToolSettings.homebrewFFmpegPath {
            settings.tools.ffmpegPath = ToolSettings.defaultFFmpegPath(fileExists: fileExists)
        }
        return settings
    }
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
    var cpuThreads: Int

    init(
        backend: ASRBackend,
        model: String,
        device: String,
        computeType: String,
        language: String,
        vadEnabled: Bool,
        beamSize: Int,
        cpuThreads: Int = 8
    ) {
        self.backend = backend
        self.model = model
        self.device = device
        self.computeType = computeType
        self.language = language
        self.vadEnabled = vadEnabled
        self.beamSize = beamSize
        self.cpuThreads = cpuThreads
    }

    enum CodingKeys: String, CodingKey {
        case backend
        case model
        case device
        case computeType
        case language
        case vadEnabled
        case beamSize
        case cpuThreads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backend = try container.decode(ASRBackend.self, forKey: .backend)
        model = try container.decode(String.self, forKey: .model)
        device = try container.decode(String.self, forKey: .device)
        computeType = try container.decode(String.self, forKey: .computeType)
        language = try container.decode(String.self, forKey: .language)
        vadEnabled = try container.decode(Bool.self, forKey: .vadEnabled)
        beamSize = try container.decode(Int.self, forKey: .beamSize)
        cpuThreads = try container.decodeIfPresent(Int.self, forKey: .cpuThreads) ?? 8
    }
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
    static let ffmpegFullPath = "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"
    static let homebrewFFmpegPath = "/opt/homebrew/bin/ffmpeg"

    var ffmpegPath: String

    static func defaultFFmpegPath(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> String {
        if fileExists(ffmpegFullPath) {
            return ffmpegFullPath
        }
        return homebrewFFmpegPath
    }
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
