import Foundation
import Observation

@Observable
final class JobStore {
    var draft = JobDraft(audioURL: nil, imageURL: nil, outputDirectory: nil, settings: .defaults)
    var validationErrors: [JobValidationError] = []
    var events: [WorkerEvent] = []
    var recentJobs: [RecentJob] = []
    var isRunning = false
    var currentProgress: Double? {
        events.reversed().compactMap(\.progress).first
    }
    var statusMessage: String {
        events.reversed().compactMap(\.message).first ?? (isRunning ? "正在准备任务" : "等待开始")
    }

    private let validator: JobValidator
    private let writer = JobFileWriter()
    private let worker: any PythonWorkerRunning
    private let transcriber: any NativeTranscriptionService
    private let apiKeyStore: any APIKeyStore
    private let settingsStore: any AppSettingsStore
    private let recentJobStore: any RecentJobStore
    private let toolFileExists: (String) -> Bool
    private var activeJobID: UUID?
    private let maximumRecentJobs = 20

    init(
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        settingsStore: any AppSettingsStore = UserDefaultsAppSettingsStore(),
        worker: any PythonWorkerRunning = PythonWorkerClient(),
        transcriber: any NativeTranscriptionService = WhisperKitTranscriptionService(),
        recentJobStore: any RecentJobStore = UserDefaultsRecentJobStore(),
        toolFileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) {
        self.apiKeyStore = apiKeyStore
        self.settingsStore = settingsStore
        self.worker = worker
        self.transcriber = transcriber
        self.recentJobStore = recentJobStore
        self.toolFileExists = toolFileExists
        self.validator = JobValidator(fileExists: toolFileExists)
        recentJobs = (try? recentJobStore.load()) ?? []
        if let settings = try? settingsStore.load() {
            let resolvedSettings = settings.resolvingAvailableToolDefaults(fileExists: toolFileExists)
            draft.settings = resolvedSettings
            if resolvedSettings != settings {
                try? settingsStore.save(resolvedSettings)
            }
        }
        draft.outputDirectory = defaultOutputDirectory()
    }

    func validate() {
        validationErrors = validator.validate(draft)
    }

    func canStart() -> Bool {
        validator.validate(draft).isEmpty && !isRunning
    }

    func append(event: WorkerEvent) {
        events.append(event)
        if event.type == .jobFinished || event.type == .stageFailed {
            isRunning = false
            updateActiveRecentJob(
                status: event.type == .jobFinished ? .finished : .failed,
                statusMessage: event.message ?? (event.type == .jobFinished ? "任务已完成" : "任务失败")
            )
        }
    }

    func saveSettings() {
        try? settingsStore.save(draft.settings)
    }

    func startProcessing() {
        validate()
        guard validationErrors.isEmpty else {
            return
        }

        do {
            let job = try validator.makeJob(from: draft)
            let artifacts = try writer.write(job)
            isRunning = true
            activeJobID = job.id
            events.removeAll()
            recordRecentJob(
                RecentJob(
                    id: job.id,
                    audioPath: job.audioPath,
                    imagePath: job.imagePath,
                    outputDirectory: job.outputDirectory,
                    workingDirectory: artifacts.workingDirectory.path,
                    translationProvider: job.settings.translation.selectedProvider,
                    createdAt: job.createdAt,
                    status: .running,
                    statusMessage: "正在处理"
                )
            )
            Task { [weak self] in
                guard let self else { return }
                do {
                    if job.settings.asr.backend == .whisperKit {
                        await MainActor.run {
                            self.append(
                                event: WorkerEvent(
                                    type: .stageStarted,
                                    stage: "asr",
                                    message: "正在用 WhisperKit/Core ML 识别日语音频",
                                    progress: 0.05,
                                    path: nil
                                )
                            )
                        }
                        let transcriptURL = artifacts.workingDirectory.appendingPathComponent("transcript.ja.json")
                        try await transcriber.transcribe(
                            audioURL: URL(fileURLWithPath: job.audioPath),
                            settings: job.settings.asr,
                            outputURL: transcriptURL,
                            projectRoot: projectRoot()
                        )
                        await MainActor.run {
                            self.append(
                                event: WorkerEvent(
                                    type: .artifactCreated,
                                    stage: "asr",
                                    message: "WhisperKit 日语转写已完成",
                                    progress: 0.40,
                                    path: transcriptURL.path
                                )
                            )
                        }
                    }

                    let apiKey = job.settings.video.requiresTranslation
                        ? try apiKeyStore.loadTranslationAPIKey(for: job.settings.translation.selectedProvider)
                        : nil
                    let workerDirectory = projectRoot()
                        .appendingPathComponent("worker", isDirectory: true)
                    let request = WorkerLaunchRequest(
                        condaPath: job.settings.conda.executablePath,
                        environmentName: job.settings.conda.environmentName,
                        workerDirectory: workerDirectory,
                        jobFile: artifacts.jobFile,
                        environment: apiKey.map { ["OTOCHEF_TRANSLATION_API_KEY": $0] } ?? [:]
                    )
                    try worker.run(request) { [weak self] event in
                        DispatchQueue.main.async {
                            self?.append(event: event)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.append(
                            event: WorkerEvent(
                                type: .stageFailed,
                                stage: "swift",
                                message: error.localizedDescription,
                                progress: nil,
                                path: nil
                            )
                        )
                    }
                }
            }
        } catch {
            isRunning = false
            events.append(
                WorkerEvent(
                    type: .stageFailed,
                    stage: "swift",
                    message: error.localizedDescription,
                    progress: nil,
                    path: nil
                )
            )
        }
    }

    private func recordRecentJob(_ job: RecentJob) {
        recentJobs.removeAll { $0.id == job.id }
        recentJobs.insert(job, at: 0)
        if recentJobs.count > maximumRecentJobs {
            recentJobs.removeLast(recentJobs.count - maximumRecentJobs)
        }
        saveRecentJobs()
    }

    private func updateActiveRecentJob(status: RecentJobStatus, statusMessage: String) {
        guard let activeJobID,
              let index = recentJobs.firstIndex(where: { $0.id == activeJobID }) else {
            return
        }
        recentJobs[index].status = status
        recentJobs[index].statusMessage = statusMessage
        saveRecentJobs()
        if status != .running {
            self.activeJobID = nil
        }
    }

    private func saveRecentJobs() {
        try? recentJobStore.save(recentJobs)
    }

    private func projectRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func defaultOutputDirectory() -> URL {
        projectRoot().appendingPathComponent("output", isDirectory: true)
    }
}

extension JobStore: @unchecked Sendable { }
