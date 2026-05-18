import XCTest
@testable import OtoChefApp

final class JobStoreTests: XCTestCase {
    func testInitLoadsPersistedSettings() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.beamSize = 4
        settings.translation.endpoint = "https://persisted.example.com/v1"
        try settingsStore.save(settings)

        let store = JobStore(apiKeyStore: MemoryAPIKeyStore(), settingsStore: settingsStore)

        XCTAssertEqual(store.draft.settings.asr.beamSize, 4)
        XCTAssertEqual(store.draft.settings.translation.endpoint, "https://persisted.example.com/v1")
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
        store.draft.settings.translation.model = "saved-model"

        store.saveSettings()

        XCTAssertEqual(try settingsStore.load()?.translation.model, "saved-model")
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
