import XCTest
@testable import OtoChefApp

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsUseWhisperKitLargeV3CoreML() throws {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.asr.backend, .whisperKit)
        XCTAssertEqual(settings.asr.model, "large-v3-v20240930_626MB")
        XCTAssertEqual(settings.asr.modelFolder, "Models/whisperkit")
        XCTAssertEqual(settings.asr.device, "coreML")
        XCTAssertEqual(settings.asr.computeType, "all")
        XCTAssertEqual(settings.asr.beamSize, 1)
        XCTAssertEqual(settings.asr.cpuThreads, 8)
        XCTAssertEqual(settings.conda.environmentName, "otochef")
        XCTAssertEqual(settings.video.width, 1920)
        XCTAssertEqual(settings.video.height, 1080)
        XCTAssertEqual(settings.video.subtitleOutputMode, .external)
    }

    func testWhisperKitModelOptionsExposeExpectedProjectLocalModels() {
        XCTAssertEqual(
            ASRSettings.whisperKitModelOptions,
            [
                "large-v3-v20240930_626MB",
                "large-v3-v20240930_turbo_632MB",
                "tiny"
            ]
        )
    }

    func testTranslationSettingsProvideDefaultsForEveryProvider() throws {
        let settings = AppSettings.defaults.translation

        XCTAssertEqual(settings.selectedProvider, .ollama)
        XCTAssertEqual(
            TranslationProvider.allCases.map(\.label),
            [
                "OpenAI-GPT",
                "Anthropic-Claude",
                "Google-Gemini",
                "DeepSeek",
                "Ollama",
                "LM Studio",
                "OpenAI兼容"
            ]
        )
        XCTAssertEqual(Set(settings.providerConfigurations.map(\.provider)), Set(TranslationProvider.allCases))
        XCTAssertEqual(settings.configuration(for: .deepSeek).baseURL, "https://api.deepseek.com")
        XCTAssertEqual(settings.configuration(for: .openAI).baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(settings.configuration(for: .claude).baseURL, "https://api.anthropic.com")
        XCTAssertEqual(settings.configuration(for: .gemini).baseURL, "https://generativelanguage.googleapis.com")
        XCTAssertEqual(settings.configuration(for: .ollama).baseURL, "http://localhost:11434/v1")
        XCTAssertEqual(settings.configuration(for: .lmStudio).baseURL, "http://localhost:1234/v1")
    }

    func testUpdatingOneProviderConfigurationDoesNotAffectAnotherProvider() throws {
        var settings = AppSettings.defaults.translation

        settings.updateConfiguration(for: .deepSeek) { configuration in
            configuration.baseURL = "https://custom.deepseek.example"
            configuration.model = "deepseek-custom"
        }

        XCTAssertEqual(settings.configuration(for: .deepSeek).baseURL, "https://custom.deepseek.example")
        XCTAssertEqual(settings.configuration(for: .deepSeek).model, "deepseek-custom")
        XCTAssertEqual(settings.configuration(for: .openAI).baseURL, "https://api.openai.com/v1")
        XCTAssertNotEqual(settings.configuration(for: .openAI).model, "deepseek-custom")
    }

    func testToolSettingsPreferFFmpegFullWhenAvailable() {
        let path = ToolSettings.defaultFFmpegPath(fileExists: { $0 == ToolSettings.ffmpegFullPath })

        XCTAssertEqual(path, ToolSettings.ffmpegFullPath)
    }

    func testToolSettingsFallbackToHomebrewFFmpegWhenFFmpegFullIsMissing() {
        let path = ToolSettings.defaultFFmpegPath(fileExists: { _ in false })

        XCTAssertEqual(path, ToolSettings.homebrewFFmpegPath)
    }

    func testResolvingToolDefaultsMigratesOldDefaultFFmpegPathToFFmpegFull() {
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = ToolSettings.homebrewFFmpegPath

        let resolved = settings.resolvingAvailableToolDefaults(fileExists: { $0 == ToolSettings.ffmpegFullPath })

        XCTAssertEqual(resolved.tools.ffmpegPath, ToolSettings.ffmpegFullPath)
    }

    func testResolvingToolDefaultsPreservesCustomFFmpegPath() {
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = "/custom/bin/ffmpeg"

        let resolved = settings.resolvingAvailableToolDefaults(fileExists: { $0 == ToolSettings.ffmpegFullPath })

        XCTAssertEqual(resolved.tools.ffmpegPath, "/custom/bin/ffmpeg")
    }

    func testResolvingDefaultsMigratesOldWhisperKitApplicationSupportModelFolder() {
        var settings = AppSettings.defaults
        settings.asr.modelFolder = "~/Library/Application Support/OtoChef/Models/whisperkit"

        let resolved = settings.resolvingAvailableToolDefaults()

        XCTAssertEqual(resolved.asr.modelFolder, "Models/whisperkit")
    }

    func testResolvingDefaultsKeepsWhisperKitModelsUnderProjectDirectory() {
        var settings = AppSettings.defaults
        settings.asr.modelFolder = "/custom/models"

        let resolved = settings.resolvingAvailableToolDefaults()

        XCTAssertEqual(resolved.asr.modelFolder, "Models/whisperkit")
    }

    func testASRSettingsDecodeDefaultsCPUThreadsForOlderSavedSettings() throws {
        let json = """
        {
          "backend": "fasterWhisper",
          "model": "Systran/faster-whisper-large-v3",
          "device": "cpu",
          "computeType": "int8",
          "language": "ja",
          "vadEnabled": true,
          "beamSize": 1
        }
        """

        let settings = try JSONDecoder().decode(ASRSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.cpuThreads, 8)
    }

    func testASRSettingsDecodeDefaultsModelFolderForOlderSavedSettings() throws {
        let json = """
        {
          "backend": "whisperKit",
          "model": "large-v3-v20240930_626MB",
          "device": "coreML",
          "computeType": "all",
          "language": "ja",
          "vadEnabled": true,
          "beamSize": 1,
          "cpuThreads": 8
        }
        """

        let settings = try JSONDecoder().decode(ASRSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.modelFolder, ASRSettings.defaultWhisperKitModelFolder)
    }

    func testVideoSettingsDecodeDefaultsSubtitleOutputModeForOlderSavedSettings() throws {
        let json = """
        {
          "width": 1920,
          "height": 1080,
          "imageFit": "contain",
          "backgroundColor": "black"
        }
        """

        let settings = try JSONDecoder().decode(VideoSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.subtitleOutputMode, .external)
    }

    func testTranslationSettingsDecodeOlderEndpointModelShapeIntoDefaults() throws {
        let json = """
        {
          "backend": "api",
          "endpoint": "https://legacy.example.com/v1",
          "model": "legacy-model",
          "prompt": "Legacy prompt",
          "timeoutSeconds": 90,
          "retryLimit": 3
        }
        """

        let settings = try JSONDecoder().decode(TranslationSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.selectedProvider, .openAICompatible)
        XCTAssertEqual(settings.configuration(for: .openAICompatible).baseURL, "https://legacy.example.com/v1")
        XCTAssertEqual(settings.configuration(for: .openAICompatible).model, "legacy-model")
        XCTAssertEqual(settings.prompt, "Legacy prompt")
        XCTAssertEqual(settings.timeoutSeconds, 90)
        XCTAssertEqual(settings.retryLimit, 3)
    }
}
