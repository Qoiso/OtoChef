import Foundation

struct JobValidator {
    private let fileExists: (String) -> Bool

    init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.fileExists = fileExists
    }

    func validate(_ draft: JobDraft) -> [JobValidationError] {
        var errors: [JobValidationError] = []
        let outputSettings = draft.settings.outputSettings(for: draft.inputKind)

        if draft.inputKind == .audio && (draft.audioURL == nil || !fileExists(draft.audioURL?.path ?? "")) {
            errors.append(.missingAudio)
        }
        if draft.inputKind == .video && (draft.videoURL == nil || !fileExists(draft.videoURL?.path ?? "")) {
            errors.append(.missingVideo)
        }
        if draft.inputKind == .audio && outputSettings.includesVideo && (draft.imageURL == nil || !fileExists(draft.imageURL?.path ?? "")) {
            errors.append(.missingImage)
        }
        if draft.outputDirectory == nil {
            errors.append(.missingOutputDirectory)
        }
        if outputSettings.outputFiles.isEmpty {
            errors.append(.missingOutputFile)
        }
        if draft.settings.asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingASRModel)
        }
        let environmentPath = draft.settings.conda.environmentPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if environmentPath.isEmpty {
            let condaPath = draft.settings.conda.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if condaPath.isEmpty || !fileExists(condaPath) {
                errors.append(.missingCondaExecutable)
            }
            if draft.settings.conda.environmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.missingCondaEnvironment)
            }
        } else {
            let pythonPath = URL(fileURLWithPath: environmentPath, isDirectory: true)
                .appendingPathComponent("bin/python")
                .path
            if !fileExists(pythonPath) {
                errors.append(.missingCondaExecutable)
            }
        }
        let ffmpegPath = draft.settings.tools.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if outputSettings.includesVideo && (ffmpegPath.isEmpty || !fileExists(ffmpegPath)) {
            errors.append(.missingFFmpeg)
        }
        let translationConfiguration = draft.settings.translation.activeConfiguration
        if outputSettings.requiresTranslation && translationConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTranslationEndpoint)
        }
        if outputSettings.requiresTranslation && translationConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTranslationModel)
        }

        return errors
    }

    func makeJob(from draft: JobDraft, now: Date = Date()) throws -> OtoChefJob {
        let errors = validate(draft)
        if let first = errors.first {
            throw first
        }

        return OtoChefJob(
            id: UUID(),
            inputKind: draft.inputKind,
            audioPath: draft.inputKind == .audio ? draft.audioURL!.path : draft.videoURL!.path,
            videoPath: draft.inputKind == .video ? draft.videoURL!.path : nil,
            imagePath: draft.inputKind == .audio ? draft.imageURL?.path ?? "" : "",
            outputDirectory: draft.outputDirectory!.path,
            workingDirectory: nil,
            settings: draft.settings.workerSettings(for: draft.inputKind),
            createdAt: now
        )
    }
}

extension JobValidationError: Error { }
