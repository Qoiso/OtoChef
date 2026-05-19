import XCTest
@testable import OtoChefApp

final class JobStoreTests: XCTestCase {
    func testInitLoadsPersistedSettings() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.beamSize = 4
        settings.translation.updateConfiguration(for: .openAICompatible) { configuration in
            configuration.baseURL = "https://persisted.example.com/v1"
        }
        try settingsStore.save(settings)

        let store = JobStore(apiKeyStore: MemoryAPIKeyStore(), settingsStore: settingsStore)

        XCTAssertEqual(store.draft.settings.asr.beamSize, 4)
        XCTAssertEqual(
            store.draft.settings.translation.configuration(for: .openAICompatible).baseURL,
            "https://persisted.example.com/v1"
        )
    }

    func testInitMigratesPersistedOldDefaultFFmpegPathWhenFFmpegFullExists() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = ToolSettings.homebrewFFmpegPath
        try settingsStore.save(settings)

        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            toolFileExists: { $0 == ToolSettings.ffmpegFullPath }
        )

        XCTAssertEqual(store.draft.settings.tools.ffmpegPath, ToolSettings.ffmpegFullPath)
    }

    func testInitSavesMigratedFFmpegPath() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = ToolSettings.homebrewFFmpegPath
        try settingsStore.save(settings)

        _ = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            toolFileExists: { $0 == ToolSettings.ffmpegFullPath }
        )

        XCTAssertEqual(try settingsStore.load()?.tools.ffmpegPath, ToolSettings.ffmpegFullPath)
    }

    func testInitPreservesPersistedCustomFFmpegPath() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = "/custom/bin/ffmpeg"
        try settingsStore.save(settings)

        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            toolFileExists: { $0 == ToolSettings.ffmpegFullPath }
        )

        XCTAssertEqual(store.draft.settings.tools.ffmpegPath, "/custom/bin/ffmpeg")
    }

    func testSaveSettingsPersistsDraftSettings() throws {
        let settingsStore = MemoryAppSettingsStore()
        let store = JobStore(apiKeyStore: MemoryAPIKeyStore(), settingsStore: settingsStore)
        store.draft.settings.translation.updateConfiguration(for: .ollama) { configuration in
            configuration.model = "saved-model"
        }

        store.saveSettings()

        XCTAssertEqual(try settingsStore.load()?.translation.configuration(for: .ollama).model, "saved-model")
    }

    func testStartProcessingPassesOnlySelectedProviderAPIKey() async throws {
        let apiKeyStore = MemoryAPIKeyStore()
        try apiKeyStore.saveTranslationAPIKey("deepseek-key", for: .deepSeek)
        try apiKeyStore.saveTranslationAPIKey("openai-key", for: .openAI)
        let worker = CapturingPythonWorker()
        let didRunWorker = expectation(description: "worker ran")
        worker.onRun = { didRunWorker.fulfill() }
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        settings.translation.selectedProvider = .deepSeek
        try settingsStore.save(settings)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: apiKeyStore,
            settingsStore: settingsStore,
            worker: worker,
            transcriber: StubNativeTranscriptionService(),
            toolFileExists: { _ in true }
        )
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
        store.draft.outputDirectory = outputDirectory

        store.startProcessing()
        await fulfillment(of: [didRunWorker], timeout: 2)

        XCTAssertEqual(worker.lastRequest?.environment["OTOCHEF_TRANSLATION_API_KEY"], "deepseek-key")
    }

    func testAppendTracksLatestProgressAndStatusMessage() {
        let store = JobStore(apiKeyStore: MemoryAPIKeyStore(), settingsStore: MemoryAppSettingsStore())

        store.append(
            event: WorkerEvent(
                type: .stageStarted,
                stage: "asr",
                message: "正在加载 ASR 模型并识别日语音频",
                progress: 0.05,
                path: nil
            )
        )
        store.append(
            event: WorkerEvent(
                type: .artifactCreated,
                stage: "asr",
                message: "日语转写已完成",
                progress: 0.40,
                path: "/tmp/transcript.ja.json"
            )
        )

        XCTAssertEqual(store.currentProgress, 0.40)
        XCTAssertEqual(store.statusMessage, "日语转写已完成")
    }
}

private final class CapturingPythonWorker: PythonWorkerRunning {
    var onRun: (() -> Void)?
    private(set) var lastRequest: WorkerLaunchRequest?

    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        lastRequest = request
        onRun?()
    }
}

private struct StubNativeTranscriptionService: NativeTranscriptionService {
    func transcribe(audioURL: URL, settings: ASRSettings, outputURL: URL, projectRoot: URL) async throws { }
}
