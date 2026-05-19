import Foundation

struct AppSettings: Codable, Equatable {
    var asr: ASRSettings
    var translation: TranslationSettings
    var conda: CondaSettings
    var tools: ToolSettings
    var video: VideoSettings

    static let defaults = AppSettings(
        asr: ASRSettings(
            backend: .whisperKit,
            model: "large-v3-v20240930_626MB",
            modelFolder: ASRSettings.defaultWhisperKitModelFolder,
            device: "coreML",
            computeType: "all",
            language: "ja",
            vadEnabled: true,
            beamSize: 1,
            cpuThreads: 8
        ),
        translation: TranslationSettings(
            backend: .api,
            selectedProvider: .ollama,
            providerConfigurations: TranslationSettings.defaultProviderConfigurations,
            prompt: TranslationSettings.defaultPrompt,
            timeoutSeconds: 120,
            retryLimit: 2
        ),
        conda: CondaSettings(executablePath: "/opt/homebrew/bin/conda", environmentName: "otochef"),
        tools: ToolSettings(ffmpegPath: ToolSettings.defaultFFmpegPath()),
        video: VideoSettings(width: 1920, height: 1080, imageFit: .contain, backgroundColor: "black", subtitleOutputMode: .external)
    )

    func resolvingAvailableToolDefaults(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> AppSettings {
        var settings = self
        if settings.tools.ffmpegPath == ToolSettings.homebrewFFmpegPath {
            settings.tools.ffmpegPath = ToolSettings.defaultFFmpegPath(fileExists: fileExists)
        }
        if settings.asr.backend == .fasterWhisper {
            settings.asr = AppSettings.defaults.asr
        } else if settings.asr.modelFolder != ASRSettings.defaultWhisperKitModelFolder {
            settings.asr.modelFolder = ASRSettings.defaultWhisperKitModelFolder
        }
        return settings
    }
}

enum ASRBackend: String, Codable, Equatable {
    case whisperKit
    case fasterWhisper
}

struct ASRSettings: Codable, Equatable {
    static let defaultWhisperKitModelFolder = "Models/whisperkit"
    static let legacyWhisperKitModelFolder = "~/Library/Application Support/OtoChef/Models/whisperkit"
    static let whisperKitModelOptions = [
        "large-v3-v20240930_626MB",
        "large-v3-v20240930_turbo_632MB",
        "tiny"
    ]

    var backend: ASRBackend
    var model: String
    var modelFolder: String
    var device: String
    var computeType: String
    var language: String
    var vadEnabled: Bool
    var beamSize: Int
    var cpuThreads: Int

    init(
        backend: ASRBackend,
        model: String,
        modelFolder: String = ASRSettings.defaultWhisperKitModelFolder,
        device: String,
        computeType: String,
        language: String,
        vadEnabled: Bool,
        beamSize: Int,
        cpuThreads: Int = 8
    ) {
        self.backend = backend
        self.model = model
        self.modelFolder = modelFolder
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
        case modelFolder
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
        modelFolder = try container.decodeIfPresent(String.self, forKey: .modelFolder) ?? Self.defaultWhisperKitModelFolder
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

enum TranslationProvider: String, Codable, Equatable, CaseIterable, Identifiable {
    case openAI
    case claude
    case gemini
    case deepSeek
    case ollama
    case lmStudio
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI:
            return "OpenAI-GPT"
        case .claude:
            return "Anthropic-Claude"
        case .gemini:
            return "Google-Gemini"
        case .deepSeek:
            return "DeepSeek"
        case .ollama:
            return "Ollama"
        case .lmStudio:
            return "LM Studio"
        case .openAICompatible:
            return "OpenAI兼容"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .deepSeek, .openAI, .claude, .gemini:
            return true
        case .ollama, .lmStudio, .openAICompatible:
            return false
        }
    }

    var acceptsOptionalAPIKey: Bool {
        switch self {
        case .lmStudio, .openAICompatible:
            return true
        default:
            return requiresAPIKey
        }
    }
}

struct TranslationProviderConfiguration: Codable, Equatable, Identifiable {
    var provider: TranslationProvider
    var baseURL: String
    var model: String

    var id: TranslationProvider { provider }
}

struct TranslationSettings: Codable, Equatable {
    var backend: TranslationBackend
    var selectedProvider: TranslationProvider
    var providerConfigurations: [TranslationProviderConfiguration]
    var prompt: String
    var timeoutSeconds: Int
    var retryLimit: Int

    var activeConfiguration: TranslationProviderConfiguration {
        configuration(for: selectedProvider)
    }

    static let defaultPrompt = "Translate each Japanese subtitle segment into natural Simplified Chinese. Preserve IDs. Return only a JSON array of objects with id and text."

    static let defaultProviderConfigurations = [
        TranslationProviderConfiguration(provider: .deepSeek, baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash"),
        TranslationProviderConfiguration(provider: .openAI, baseURL: "https://api.openai.com/v1", model: "gpt-5"),
        TranslationProviderConfiguration(provider: .claude, baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-5-20250929"),
        TranslationProviderConfiguration(provider: .gemini, baseURL: "https://generativelanguage.googleapis.com", model: "gemini-2.0-flash"),
        TranslationProviderConfiguration(provider: .ollama, baseURL: "http://localhost:11434/v1", model: "qwen2.5:7b"),
        TranslationProviderConfiguration(provider: .lmStudio, baseURL: "http://localhost:1234/v1", model: "model-identifier"),
        TranslationProviderConfiguration(provider: .openAICompatible, baseURL: "https://api.example.com/v1", model: "model-name")
    ]

    init(
        backend: TranslationBackend,
        selectedProvider: TranslationProvider,
        providerConfigurations: [TranslationProviderConfiguration],
        prompt: String,
        timeoutSeconds: Int,
        retryLimit: Int
    ) {
        self.backend = backend
        self.selectedProvider = selectedProvider
        self.providerConfigurations = Self.mergedWithDefaults(providerConfigurations)
        self.prompt = prompt
        self.timeoutSeconds = timeoutSeconds
        self.retryLimit = retryLimit
    }

    enum CodingKeys: String, CodingKey {
        case backend
        case selectedProvider
        case providerConfigurations
        case endpoint
        case model
        case prompt
        case timeoutSeconds
        case retryLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backend = try container.decodeIfPresent(TranslationBackend.self, forKey: .backend) ?? .api
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? Self.defaultPrompt
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 120
        retryLimit = try container.decodeIfPresent(Int.self, forKey: .retryLimit) ?? 2

        if let selectedProvider = try container.decodeIfPresent(TranslationProvider.self, forKey: .selectedProvider),
           let configurations = try container.decodeIfPresent([TranslationProviderConfiguration].self, forKey: .providerConfigurations) {
            self.selectedProvider = selectedProvider
            providerConfigurations = Self.mergedWithDefaults(configurations)
        } else {
            let legacyEndpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
            let legacyModel = try container.decodeIfPresent(String.self, forKey: .model)
            selectedProvider = .openAICompatible
            var configurations = Self.defaultProviderConfigurations
            if legacyEndpoint != nil || legacyModel != nil {
                configurations.removeAll { $0.provider == .openAICompatible }
                configurations.append(
                    TranslationProviderConfiguration(
                        provider: .openAICompatible,
                        baseURL: legacyEndpoint ?? "https://api.example.com/v1",
                        model: legacyModel ?? "model-name"
                    )
                )
            }
            providerConfigurations = Self.mergedWithDefaults(configurations)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backend, forKey: .backend)
        try container.encode(selectedProvider, forKey: .selectedProvider)
        try container.encode(providerConfigurations, forKey: .providerConfigurations)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(retryLimit, forKey: .retryLimit)
    }

    func configuration(for provider: TranslationProvider) -> TranslationProviderConfiguration {
        providerConfigurations.first { $0.provider == provider }
            ?? Self.defaultProviderConfigurations.first { $0.provider == provider }!
    }

    mutating func updateConfiguration(
        for provider: TranslationProvider,
        mutate: (inout TranslationProviderConfiguration) -> Void
    ) {
        var configuration = configuration(for: provider)
        mutate(&configuration)
        providerConfigurations.removeAll { $0.provider == provider }
        providerConfigurations.append(configuration)
        providerConfigurations = Self.mergedWithDefaults(providerConfigurations)
    }

    static func mergedWithDefaults(_ configurations: [TranslationProviderConfiguration]) -> [TranslationProviderConfiguration] {
        TranslationProvider.allCases.map { provider in
            configurations.first { $0.provider == provider }
                ?? defaultProviderConfigurations.first { $0.provider == provider }!
        }
    }
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
    var subtitleOutputMode: SubtitleOutputMode

    init(
        width: Int,
        height: Int,
        imageFit: ImageFit,
        backgroundColor: String,
        subtitleOutputMode: SubtitleOutputMode = .external
    ) {
        self.width = width
        self.height = height
        self.imageFit = imageFit
        self.backgroundColor = backgroundColor
        self.subtitleOutputMode = subtitleOutputMode
    }

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case imageFit
        case backgroundColor
        case subtitleOutputMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        imageFit = try container.decode(ImageFit.self, forKey: .imageFit)
        backgroundColor = try container.decode(String.self, forKey: .backgroundColor)
        subtitleOutputMode = try container.decodeIfPresent(SubtitleOutputMode.self, forKey: .subtitleOutputMode) ?? .external
    }
}

enum SubtitleOutputMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case external
    case mkvSoftAss
    case mp4HardSubtitles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .external:
            return "外挂字幕"
        case .mkvSoftAss:
            return "MKV + ASS 软字幕"
        case .mp4HardSubtitles:
            return "MP4 硬字幕"
        }
    }
}
