import Foundation

struct JobValidator {
    private let fileExists: (String) -> Bool

    init(fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        self.fileExists = fileExists
    }

    func validate(_ draft: JobDraft) -> [JobValidationError] {
        var errors: [JobValidationError] = []

        if draft.audioURL == nil || !fileExists(draft.audioURL?.path ?? "") {
            errors.append(.missingAudio)
        }
        if draft.imageURL == nil || !fileExists(draft.imageURL?.path ?? "") {
            errors.append(.missingImage)
        }
        if draft.outputDirectory == nil || !fileExists(draft.outputDirectory?.path ?? "") {
            errors.append(.missingOutputDirectory)
        }
        if draft.settings.asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingASRModel)
        }
        let condaPath = draft.settings.conda.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if condaPath.isEmpty || !fileExists(condaPath) {
            errors.append(.missingCondaExecutable)
        }
        if draft.settings.conda.environmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingCondaEnvironment)
        }
        let ffmpegPath = draft.settings.tools.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if ffmpegPath.isEmpty || !fileExists(ffmpegPath) {
            errors.append(.missingFFmpeg)
        }
        let translationConfiguration = draft.settings.translation.activeConfiguration
        if translationConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTranslationEndpoint)
        }
        if translationConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            audioPath: draft.audioURL!.path,
            imagePath: draft.imageURL!.path,
            outputDirectory: draft.outputDirectory!.path,
            settings: draft.settings,
            createdAt: now
        )
    }
}

extension JobValidationError: Error { }
