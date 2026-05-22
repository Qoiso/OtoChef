import Foundation
import Observation

@Observable
final class JobStore {
    var draft = JobDraft(audioURL: nil, imageURL: nil, outputDirectory: nil, settings: .defaults)
    var validationErrors: [JobValidationError] = []
    var events: [WorkerEvent] = []
    var logEntries: [JobLogEntry] = []
    var recentJobs: [RecentJob] = []
    var isRunning = false
    var runningRecentJobs: [RecentJob] {
        recentJobs.filter { $0.status == .running }
    }
    var completedRecentJobs: [RecentJob] {
        recentJobs.filter { $0.status == .finished }
    }
    var developerLogText = ""
    var developerLogFileURL: URL?
    private var developerLogJobID: UUID?
    var userLogText: String {
        let lines = logEntries.suffix(40).compactMap(Self.userFacingLogLine)
        guard !lines.isEmpty else {
            return "等待任务开始。"
        }
        return lines.joined(separator: "\n")
    }
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
    private var runningJobIDs: Set<UUID> = []
    private var completedJobIDs: Set<UUID> = []
    private var queuedJobs: [QueuedJob] = []
    private var resourceReleaseTask: Task<Void, Never>?
    private let maximumRecentJobs = 20

    private struct QueuedJob {
        var job: OtoChefJob
        var artifacts: JobArtifacts
        var blockedBy: Set<UUID>
    }

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
        validator.validate(draft).isEmpty
    }

    func append(event: WorkerEvent) {
        events.append(event)
        recordLog(event: event)
        if let activeJobID {
            updateRecentJob(
                id: activeJobID,
                status: nil,
                statusMessage: event.message,
                progress: event.progress
            )
        }
        if event.type == .jobFinished || event.type == .stageFailed {
            if let activeJobID {
                finishJob(
                    id: activeJobID,
                    status: event.type == .jobFinished ? .finished : .failed,
                    statusMessage: statusMessage(for: event),
                    progress: event.type == .jobFinished ? 1.0 : event.progress
                )
            } else {
                isRunning = false
            }
        }
    }

    func append(event: WorkerEvent, for jobID: UUID) {
        events.append(event)
        recordLog(event: event, jobID: jobID)
        if event.type == .jobFinished || event.type == .stageFailed {
            finishJob(
                id: jobID,
                status: event.type == .jobFinished ? .finished : .failed,
                statusMessage: statusMessage(for: event),
                progress: event.type == .jobFinished ? 1.0 : event.progress
            )
        } else {
            updateRecentJob(
                id: jobID,
                status: nil,
                statusMessage: event.message,
                progress: event.progress
            )
        }
    }

    func saveSettings() {
        try? settingsStore.save(draft.settings)
    }

    func clearCompletedRecentJob(id: UUID) {
        guard let index = recentJobs.firstIndex(where: { $0.id == id && $0.status == .finished }) else {
            return
        }
        recentJobs.remove(at: index)
        saveRecentJobs()
    }

    func startProcessing(mode: JobSubmissionMode = .parallel) {
        validate()
        guard validationErrors.isEmpty else {
            for error in validationErrors {
                recordStandaloneEvent(
                    WorkerEvent(
                        type: .stageFailed,
                        stage: "validation",
                        message: error.message,
                        progress: nil,
                        path: nil
                    )
                )
            }
            return
        }

        do {
            resourceReleaseTask?.cancel()
            let job = try validator.makeJob(from: draft)
            let artifacts = try writer.write(job)
            let blockers = runningJobIDs.union(queuedJobs.map(\.job.id))
            resetDeveloperLog(for: job)
            recordRecentJob(
                RecentJob(
                    id: job.id,
                    audioPath: job.audioPath,
                    imagePath: job.imagePath,
                    outputDirectory: job.outputDirectory,
                    workingDirectory: artifacts.workingDirectory.path,
                    translationProvider: job.settings.translation.selectedProvider,
                    createdAt: job.createdAt,
                    status: mode == .queued && !blockers.isEmpty ? .queued : .running,
                    statusMessage: mode == .queued && !blockers.isEmpty ? "等待前序任务完成" : "正在处理",
                    progress: mode == .queued && !blockers.isEmpty ? 0 : nil,
                    submissionMode: mode
                )
            )

            switch mode {
            case .parallel:
                startExecution(job: job, artifacts: artifacts)
            case .queued:
                queuedJobs.append(QueuedJob(job: job, artifacts: artifacts, blockedBy: blockers))
                startReadyQueuedJobs()
            }
            clearSubmittedMediaInputs()
        } catch {
            isRunning = false
            append(
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

    private func startExecution(job: OtoChefJob, artifacts: JobArtifacts) {
        runningJobIDs.insert(job.id)
        isRunning = true
        activeJobID = job.id
        updateRecentJob(id: job.id, status: .running, statusMessage: "正在处理", progress: nil)

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
                            ),
                            for: job.id
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
                            ),
                            for: job.id
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
                        self?.append(event: event, for: job.id)
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
                        ),
                        for: job.id
                    )
                }
            }
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

    private func updateRecentJob(
        id: UUID,
        status: RecentJobStatus?,
        statusMessage: String?,
        progress: Double?
    ) {
        guard let index = recentJobs.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let status {
            recentJobs[index].status = status
        }
        if let statusMessage {
            recentJobs[index].statusMessage = statusMessage
        }
        if let progress {
            recentJobs[index].progress = progress
        }
        saveRecentJobs()
    }

    private func finishJob(
        id: UUID,
        status: RecentJobStatus,
        statusMessage: String,
        progress: Double?
    ) {
        updateRecentJob(id: id, status: status, statusMessage: statusMessage, progress: progress)
        runningJobIDs.remove(id)
        completedJobIDs.insert(id)
        if activeJobID == id {
            activeJobID = runningJobIDs.first
        }
        isRunning = !runningJobIDs.isEmpty
        startReadyQueuedJobs()
        releaseResourcesIfIdle()
    }

    private func startReadyQueuedJobs() {
        while let index = queuedJobs.firstIndex(where: { $0.blockedBy.isSubset(of: completedJobIDs) }) {
            let queuedJob = queuedJobs.remove(at: index)
            startExecution(job: queuedJob.job, artifacts: queuedJob.artifacts)
        }
    }

    private func releaseResourcesIfIdle() {
        guard runningJobIDs.isEmpty && queuedJobs.isEmpty else {
            return
        }
        resourceReleaseTask?.cancel()
        resourceReleaseTask = Task { [transcriber] in
            guard !Task.isCancelled else {
                return
            }
            await transcriber.releaseResources()
        }
    }

    private func saveRecentJobs() {
        try? recentJobStore.save(recentJobs)
    }

    private func recordLog(event: WorkerEvent) {
        let entry = JobLogEntry(timestamp: Date(), event: event)
        logEntries.append(entry)
        if logEntries.count > 200 {
            logEntries.removeFirst(logEntries.count - 200)
        }
        appendDeveloperLog(entry: entry, jobID: activeJobID)
    }

    private func recordStandaloneEvent(_ event: WorkerEvent) {
        events.append(event)
        recordLog(event: event, jobID: nil)
    }

    private func recordLog(event: WorkerEvent, jobID: UUID?) {
        let entry = JobLogEntry(timestamp: Date(), event: event)
        logEntries.append(entry)
        if logEntries.count > 200 {
            logEntries.removeFirst(logEntries.count - 200)
        }
        appendDeveloperLog(entry: entry, jobID: jobID)
    }

    private func clearSubmittedMediaInputs() {
        draft.audioURL = nil
        draft.imageURL = nil
        validate()
    }

    private func resetDeveloperLog(for job: OtoChefJob) {
        let logURL = URL(fileURLWithPath: job.outputDirectory, isDirectory: true)
            .appendingPathComponent(".otochef", isDirectory: true)
            .appendingPathComponent("latest-run.log")
        developerLogFileURL = logURL
        developerLogJobID = job.id
        developerLogText = [
            "OtoChef latest run log",
            "started_at=\(Self.iso8601String(for: job.createdAt))",
            "job_id=\(job.id.uuidString)",
            "audio_path=\(job.audioPath)",
            "image_path=\(job.imagePath)",
            "output_directory=\(job.outputDirectory)",
            ""
        ].joined(separator: "\n")
        writeDeveloperLog()
    }

    private func appendDeveloperLog(entry: JobLogEntry, jobID: UUID?) {
        guard developerLogFileURL != nil else {
            return
        }
        if let developerLogJobID, let jobID, developerLogJobID != jobID {
            return
        }
        let event = entry.event
        let jobIDText = jobID?.uuidString ?? "unknown"
        let stageText = event.stage ?? "-"
        let messageText = event.message ?? "-"
        let progressText = event.progress.map { String($0) } ?? "-"
        let pathText = event.path ?? "-"
        let fields = [
            Self.iso8601String(for: entry.timestamp),
            "job_id=\(jobIDText)",
            "type=\(event.type.rawValue)",
            "stage=\(stageText)",
            "message=\(messageText)",
            "progress=\(progressText)",
            "path=\(pathText)"
        ]
        developerLogText += fields.joined(separator: " ") + "\n"
        writeDeveloperLog()
    }

    private func writeDeveloperLog() {
        guard let developerLogFileURL else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: developerLogFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try developerLogText.write(to: developerLogFileURL, atomically: true, encoding: .utf8)
        } catch {
            // Developer log should never block a user task.
        }
    }

    private static func userFacingLogLine(for entry: JobLogEntry) -> String? {
        let event = entry.event
        guard event.type != .jobStarted else {
            return nil
        }
        let message = userFacingMessage(for: event)
        var line = "\(entry.timestamp.formatted(.dateTime.hour().minute().second())) \(message)"
        if let progress = event.progress {
            let percentage = progress.formatted(.percent.precision(.fractionLength(0)))
            line += " (\(percentage))"
        }
        return line
    }

    private func statusMessage(for event: WorkerEvent) -> String {
        switch event.type {
        case .jobFinished:
            if event.message == "Job finished" {
                return "任务已完成"
            }
            return event.message ?? "任务已完成"
        case .stageFailed:
            return event.message ?? "任务失败"
        default:
            return event.message ?? Self.fallbackUserMessage(for: event.type)
        }
    }

    private static func userFacingMessage(for event: WorkerEvent) -> String {
        switch event.type {
        case .jobFinished:
            if event.message == "Job finished" {
                return "任务已完成"
            }
            return event.message ?? "任务已完成"
        default:
            return event.message ?? fallbackUserMessage(for: event.type)
        }
    }

    private static func fallbackUserMessage(for type: WorkerEventType) -> String {
        switch type {
        case .jobStarted:
            return "任务已开始"
        case .stageStarted, .progress:
            return "正在处理"
        case .warning:
            return "注意"
        case .artifactCreated:
            return "已生成文件"
        case .stageFailed:
            return "任务失败"
        case .jobFinished:
            return "任务已完成"
        }
    }

    private static func iso8601String(for date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
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

struct JobLogEntry: Identifiable {
    let id = UUID()
    var timestamp: Date
    var event: WorkerEvent
}
