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

        XCTAssertEqual(store.draft.settings.asr.beamSize, 1)
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
        store.draft.settings.videoDownload.preset = .audioMP3

        store.saveSettings()

        XCTAssertEqual(try settingsStore.load()?.translation.configuration(for: .ollama).model, "saved-model")
        XCTAssertEqual(try settingsStore.load()?.videoDownload.preset, .audioMP3)
    }

    func testInitLoadsPersistedVideoDownloadPreset() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.videoDownload.preset = .audioOpus
        try settingsStore.save(settings)

        let store = JobStore(apiKeyStore: MemoryAPIKeyStore(), settingsStore: settingsStore)

        XCTAssertEqual(store.draft.settings.videoDownload.preset, .audioOpus)
    }

    func testInitLoadsRecentJobs() throws {
        let recentJobStore = MemoryRecentJobStore()
        let recentJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/audio.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/otochef-job",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .running,
            statusMessage: "正在处理"
        )
        try recentJobStore.save([recentJob])

        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            recentJobStore: recentJobStore
        )

        XCTAssertEqual(store.recentJobs, [recentJob])
    }

    func testStartProcessingAddsRecentJobRecord() throws {
        let recentJobStore = MemoryRecentJobStore()
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            worker: CapturingPythonWorker(),
            transcriber: StubNativeTranscriptionService(),
            recentJobStore: recentJobStore,
            toolFileExists: { _ in true }
        )
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
        store.draft.outputDirectory = outputDirectory

        store.startProcessing()

        XCTAssertEqual(store.recentJobs.count, 1)
        XCTAssertEqual(store.recentJobs.first?.audioPath, "/tmp/audio.wav")
        XCTAssertEqual(store.recentJobs.first?.imagePath, "/tmp/image.png")
        XCTAssertEqual(store.recentJobs.first?.outputDirectory, outputDirectory.path)
        XCTAssertTrue(store.recentJobs.first?.workingDirectory.hasPrefix(outputDirectory.path) == true)
        XCTAssertTrue(store.recentJobs.first?.workingDirectory.contains("/.otochef/") == true)
        XCTAssertEqual(store.recentJobs.first?.translationProvider, .ollama)
        XCTAssertEqual(store.recentJobs.first?.status, .running)
        XCTAssertEqual(try recentJobStore.load(), store.recentJobs)
    }

    func testStartProcessingClearsMediaInputsButPreservesOutputDirectoryAfterDispatch() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            worker: CapturingPythonWorker(),
            transcriber: StubNativeTranscriptionService(),
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in true }
        )
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
        store.draft.outputDirectory = outputDirectory

        store.startProcessing()

        XCTAssertNil(store.draft.audioURL)
        XCTAssertNil(store.draft.imageURL)
        XCTAssertEqual(store.draft.outputDirectory, outputDirectory)
    }

    func testStartProcessingVideoRecordsVideoJobAndClearsVideoInput() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        settings.localizedVideo.outputFiles = [.video, .bilingualSubtitles]
        try settingsStore.save(settings)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            worker: CapturingPythonWorker(),
            transcriber: StubNativeTranscriptionService(),
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in true }
        )
        store.draft.inputKind = .video
        store.draft.videoURL = URL(fileURLWithPath: "/tmp/source.mp4")
        store.draft.outputDirectory = outputDirectory

        store.startProcessing()

        XCTAssertEqual(store.recentJobs.first?.kind, .video)
        XCTAssertEqual(store.recentJobs.first?.videoURL, "/tmp/source.mp4")
        XCTAssertEqual(store.recentJobs.first?.audioPath, "/tmp/source.mp4")
        XCTAssertNil(store.draft.videoURL)
        XCTAssertEqual(store.draft.outputDirectory, outputDirectory)
    }

    func testStartProcessingLogsValidationErrorsWithoutCreatingJob() {
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            worker: CapturingPythonWorker(),
            transcriber: StubNativeTranscriptionService(),
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in false }
        )

        store.startProcessing(mode: .parallel)

        XCTAssertTrue(store.recentJobs.isEmpty)
        XCTAssertTrue(store.logEntries.contains { $0.event.message == JobValidationError.missingAudio.message })
    }

    func testStartProcessingMarksRecentJobFailedWhenWorkerThrows() async throws {
        let recentJobStore = MemoryRecentJobStore()
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            worker: ThrowingPythonWorker(),
            transcriber: StubNativeTranscriptionService(),
            recentJobStore: recentJobStore,
            toolFileExists: { _ in true }
        )
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
        store.draft.outputDirectory = outputDirectory

        store.startProcessing()

        for _ in 0..<50 where store.recentJobs.first?.status != .failed {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.recentJobs.first?.status, .failed)
        XCTAssertEqual(try recentJobStore.load().first?.status, .failed)
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

    func testParallelSubmissionStartsWhileAnotherJobIsRunning() async throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let worker = ControlledPythonWorker()
        let store = makeRunnableStore(settingsStore: settingsStore, worker: worker)

        store.startProcessing(mode: .parallel)
        try await waitUntil { worker.requests.count == 1 }
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio-2.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image-2.png")
        store.startProcessing(mode: .parallel)
        try await waitUntil { worker.requests.count == 2 }

        XCTAssertEqual(store.recentJobs.count, 2)
        XCTAssertEqual(store.recentJobs.map(\.status), [.running, .running])
    }

    func testQueuedSubmissionWaitsForPreviousJobThenStartsAutomatically() async throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let worker = ControlledPythonWorker()
        let store = makeRunnableStore(settingsStore: settingsStore, worker: worker)

        store.startProcessing(mode: .parallel)
        try await waitUntil { worker.requests.count == 1 }
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio-2.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image-2.png")
        store.startProcessing(mode: .queued)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(worker.requests.count, 1)
        XCTAssertEqual(store.recentJobs.first?.status, .queued)

        worker.finishRun(
            at: 0,
            event: WorkerEvent(
                type: .jobFinished,
                stage: nil,
                message: "第一个任务完成",
                progress: 1.0,
                path: nil
            )
        )
        try await waitUntil { worker.requests.count == 2 }

        XCTAssertEqual(store.recentJobs.first?.status, .running)
    }

    func testResourcesAreReleasedAfterSingleJobFinishes() async throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let worker = ControlledPythonWorker()
        let transcriber = ResourceTrackingTranscriptionService()
        let store = makeRunnableStore(settingsStore: settingsStore, worker: worker, transcriber: transcriber)

        store.startProcessing(mode: .parallel)
        try await waitUntil { worker.requests.count == 1 }
        worker.finishRun(
            at: 0,
            event: WorkerEvent(type: .jobFinished, stage: nil, message: "任务完成", progress: 1, path: nil)
        )

        try await waitUntil { transcriber.releaseCount == 1 }
    }

    func testResourcesAreReleasedOnlyAfterQueuedJobsAllFinish() async throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let worker = ControlledPythonWorker()
        let transcriber = ResourceTrackingTranscriptionService()
        let store = makeRunnableStore(settingsStore: settingsStore, worker: worker, transcriber: transcriber)

        store.startProcessing(mode: .parallel)
        try await waitUntil { worker.requests.count == 1 }
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio-2.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image-2.png")
        store.startProcessing(mode: .queued)

        worker.finishRun(
            at: 0,
            event: WorkerEvent(type: .jobFinished, stage: nil, message: "第一个任务完成", progress: 1, path: nil)
        )
        try await waitUntil { worker.requests.count == 2 }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(transcriber.releaseCount, 0)

        worker.finishRun(
            at: 1,
            event: WorkerEvent(type: .jobFinished, stage: nil, message: "第二个任务完成", progress: 1, path: nil)
        )

        try await waitUntil { transcriber.releaseCount == 1 }
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

    func testRunningRecentJobsIncludesOnlyRunningJobs() throws {
        let runningJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/running.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/running",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 3_000),
            status: .running,
            statusMessage: "正在处理",
            progress: 0.42
        )
        let finishedJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/finished.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/finished",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 2_000),
            status: .finished,
            statusMessage: "任务已完成",
            progress: 1
        )
        let queuedJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/queued.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/queued",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .queued,
            statusMessage: "等待前序任务完成",
            progress: 0
        )
        let recentJobStore = MemoryRecentJobStore()
        try recentJobStore.save([finishedJob, runningJob, queuedJob])

        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            recentJobStore: recentJobStore
        )

        XCTAssertEqual(store.runningRecentJobs, [runningJob])
    }

    func testCompletedRecentJobsIncludesOnlyFinishedJobs() throws {
        let finishedJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/finished.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/finished",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 2_000),
            status: .finished,
            statusMessage: "任务已完成",
            progress: 1
        )
        let runningJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/running.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/running",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .running,
            statusMessage: "正在处理",
            progress: 0.4
        )
        let failedJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/failed.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/failed",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 500),
            status: .failed,
            statusMessage: "任务失败",
            progress: 0.4
        )
        let recentJobStore = MemoryRecentJobStore()
        try recentJobStore.save([runningJob, failedJob, finishedJob])

        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            recentJobStore: recentJobStore
        )

        XCTAssertEqual(store.completedRecentJobs, [finishedJob])
    }

    func testCompletedRecentJobsAreSplitByTaskKind() throws {
        let audioJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/audio.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/audio",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 2_000),
            status: .finished,
            statusMessage: "任务已完成",
            progress: 1,
            kind: .audio
        )
        let videoJob = RecentJob(
            id: UUID(),
            audioPath: "https://example.com/watch?v=abc",
            imagePath: "",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/video",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .finished,
            statusMessage: "下载完成",
            progress: 1,
            kind: .videoDownload,
            videoURL: "https://example.com/watch?v=abc"
        )
        let recentJobStore = MemoryRecentJobStore()
        try recentJobStore.save([videoJob, audioJob])

        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            recentJobStore: recentJobStore
        )

        XCTAssertEqual(store.completedAudioJobs, [audioJob])
        XCTAssertEqual(store.completedVideoDownloadJobs, [videoJob])
    }

    func testStartVideoDownloadRecordsRecentJobAndRunsDownloader() async throws {
        let downloader = CapturingVideoDownloader()
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            videoDownloader: downloader,
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in true }
        )
        store.videoDraft.urlString = "https://example.com/watch?v=abc"
        store.videoDraft.outputDirectory = outputDirectory
        store.draft.settings.videoDownload.preset = .videoAudioMP4

        store.startVideoDownload()
        try await waitUntil { downloader.requests.count == 1 }

        XCTAssertEqual(downloader.requests.first?.url, "https://example.com/watch?v=abc")
        XCTAssertEqual(downloader.requests.first?.outputDirectory, outputDirectory)
        XCTAssertEqual(downloader.requests.first?.preset, .videoAudioMP4)
        XCTAssertEqual(store.recentJobs.first?.kind, .videoDownload)
        XCTAssertEqual(store.recentJobs.first?.videoURL, "https://example.com/watch?v=abc")
        XCTAssertEqual(store.recentJobs.first?.status, .running)
        XCTAssertEqual(store.videoDraft.urlString, "")
        XCTAssertEqual(store.videoDraft.outputDirectory, outputDirectory)
    }

    func testStartVideoDownloadLogsValidationErrorWithoutCreatingRecentJob() {
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            videoDownloader: CapturingVideoDownloader(),
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in false }
        )
        store.videoDraft.urlString = ""

        store.startVideoDownload()

        XCTAssertTrue(store.recentJobs.isEmpty)
        XCTAssertTrue(store.logEntries.contains { $0.event.message == VideoDownloadValidationError.missingURL.message })
    }

    func testUserLogTextOmitsInternalJobStartAndStagePrefix() {
        let store = JobStore(apiKeyStore: MemoryAPIKeyStore(), settingsStore: MemoryAppSettingsStore())

        store.append(
            event: WorkerEvent(
                type: .jobStarted,
                stage: nil,
                message: "Job started",
                progress: nil,
                path: nil
            )
        )
        store.append(
            event: WorkerEvent(
                type: .stageStarted,
                stage: "asr",
                message: "正在用 WhisperKit/Core ML 识别日语音频",
                progress: 0.05,
                path: nil
            )
        )

        XCTAssertFalse(store.userLogText.contains("Job started"))
        XCTAssertFalse(store.userLogText.contains("[asr]"))
        XCTAssertTrue(store.userLogText.contains("正在用 WhisperKit/Core ML 识别日语音频"))
        XCTAssertTrue(store.userLogText.contains("(5%)"))
    }

    func testDeveloperLogFileKeepsFullLatestRunEvents() throws {
        let settingsStore = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.backend = .fasterWhisper
        try settingsStore.save(settings)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            worker: CapturingPythonWorker(),
            transcriber: StubNativeTranscriptionService(),
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in true }
        )
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
        store.draft.outputDirectory = outputDirectory

        store.startProcessing()
        let jobID = try XCTUnwrap(store.recentJobs.first?.id)
        store.append(
            event: WorkerEvent(
                type: .stageStarted,
                stage: "asr",
                message: "正在识别",
                progress: 0.05,
                path: "/tmp/transcript.ja.json"
            ),
            for: jobID
        )

        let logURL = try XCTUnwrap(store.developerLogFileURL)
        let logText = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logText.contains("job_id=\(jobID.uuidString)"))
        XCTAssertTrue(logText.contains("type=stage_started"))
        XCTAssertTrue(logText.contains("stage=asr"))
        XCTAssertTrue(logText.contains("path=/tmp/transcript.ja.json"))
        XCTAssertEqual(store.developerLogText, logText)
    }

    func testClearCompletedRecentJobRemovesOnlyFinishedJobAndPersists() throws {
        let finishedJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/finished.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/finished",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 2_000),
            status: .finished,
            statusMessage: "任务已完成",
            progress: 1
        )
        let runningJob = RecentJob(
            id: UUID(),
            audioPath: "/tmp/running.wav",
            imagePath: "/tmp/image.png",
            outputDirectory: "/tmp/output",
            workingDirectory: "/tmp/output/.otochef/running",
            translationProvider: .ollama,
            createdAt: Date(timeIntervalSince1970: 1_000),
            status: .running,
            statusMessage: "正在处理",
            progress: 0.4
        )
        let recentJobStore = MemoryRecentJobStore()
        try recentJobStore.save([finishedJob, runningJob])
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: MemoryAppSettingsStore(),
            recentJobStore: recentJobStore
        )

        store.clearCompletedRecentJob(id: finishedJob.id)
        store.clearCompletedRecentJob(id: runningJob.id)

        XCTAssertEqual(store.recentJobs, [runningJob])
        XCTAssertEqual(try recentJobStore.load(), [runningJob])
    }

    private func makeRunnableStore(
        settingsStore: MemoryAppSettingsStore,
        worker: ControlledPythonWorker,
        transcriber: any NativeTranscriptionService = StubNativeTranscriptionService()
    ) -> JobStore {
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JobStore(
            apiKeyStore: MemoryAPIKeyStore(),
            settingsStore: settingsStore,
            worker: worker,
            transcriber: transcriber,
            recentJobStore: MemoryRecentJobStore(),
            toolFileExists: { _ in true }
        )
        store.draft.audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
        store.draft.imageURL = URL(fileURLWithPath: "/tmp/image.png")
        store.draft.outputDirectory = outputDirectory
        return store
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
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

private final class ControlledPythonWorker: PythonWorkerRunning {
    private(set) var requests: [WorkerLaunchRequest] = []
    private var eventHandlers: [(WorkerEvent) -> Void] = []

    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        requests.append(request)
        eventHandlers.append(onEvent)
    }

    func finishRun(at index: Int, event: WorkerEvent) {
        eventHandlers[index](event)
    }
}

private final class CapturingVideoDownloader: VideoDownloadRunning {
    private(set) var requests: [VideoDownloadRequest] = []

    func run(_ request: VideoDownloadRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        requests.append(request)
    }
}

private struct ThrowingPythonWorker: PythonWorkerRunning {
    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        throw NSError(domain: "OtoChefTests", code: 1)
    }
}

private struct StubNativeTranscriptionService: NativeTranscriptionService {
    func transcribe(audioURL: URL, settings: ASRSettings, outputURL: URL, projectRoot: URL) async throws { }
}

private final class ResourceTrackingTranscriptionService: NativeTranscriptionService {
    private let queue = DispatchQueue(label: "OtoChefTests.ResourceTrackingTranscriptionService")
    private var _releaseCount = 0
    var releaseCount: Int {
        queue.sync { _releaseCount }
    }

    func transcribe(audioURL: URL, settings: ASRSettings, outputURL: URL, projectRoot: URL) async throws { }

    func releaseResources() async {
        queue.sync {
            _releaseCount += 1
        }
    }
}
