import Foundation
import Observation

@Observable
final class JobStore {
    var draft = JobDraft(audioURL: nil, imageURL: nil, outputDirectory: nil, settings: .defaults)
    var validationErrors: [JobValidationError] = []
    var events: [WorkerEvent] = []
    var isRunning = false
    var currentProgress: Double? {
        events.reversed().compactMap(\.progress).first
    }
    var statusMessage: String {
        events.reversed().compactMap(\.message).first ?? (isRunning ? "正在准备任务" : "等待开始")
    }

    private let validator = JobValidator()
    private let writer = JobFileWriter()
    private let worker = PythonWorkerClient()
    private let apiKeyStore: any APIKeyStore
    private let settingsStore: any AppSettingsStore
    private let toolFileExists: (String) -> Bool

    init(
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        settingsStore: any AppSettingsStore = UserDefaultsAppSettingsStore(),
        toolFileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) {
        self.apiKeyStore = apiKeyStore
        self.settingsStore = settingsStore
        self.toolFileExists = toolFileExists
        if let settings = try? settingsStore.load() {
            let resolvedSettings = settings.resolvingAvailableToolDefaults(fileExists: toolFileExists)
            draft.settings = resolvedSettings
            if resolvedSettings != settings {
                try? settingsStore.save(resolvedSettings)
            }
        }
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
            let apiKey = try apiKeyStore.loadTranslationAPIKey()
            let workerDirectory = projectRoot()
                .appendingPathComponent("worker", isDirectory: true)
            let request = WorkerLaunchRequest(
                condaPath: draft.settings.conda.executablePath,
                environmentName: draft.settings.conda.environmentName,
                workerDirectory: workerDirectory,
                jobFile: artifacts.jobFile,
                environment: apiKey.map { ["OTOCHEF_TRANSLATION_API_KEY": $0] } ?? [:]
            )
            isRunning = true
            events.removeAll()
            try worker.run(request) { [weak self] event in
                DispatchQueue.main.async {
                    self?.append(event: event)
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

    private func projectRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
