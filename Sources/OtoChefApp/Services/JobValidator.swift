import Foundation

struct JobValidator {
    func validate(_ draft: JobDraft) -> [JobValidationError] {
        var errors: [JobValidationError] = []

        if draft.audioURL == nil {
            errors.append(.missingAudio)
        }
        if draft.imageURL == nil {
            errors.append(.missingImage)
        }
        if draft.outputDirectory == nil {
            errors.append(.missingOutputDirectory)
        }
        if draft.settings.asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingASRModel)
        }
        if draft.settings.conda.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingCondaExecutable)
        }
        if draft.settings.conda.environmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingCondaEnvironment)
        }
        if draft.settings.tools.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingFFmpeg)
        }
        if draft.settings.translation.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTranslationEndpoint)
        }
        if draft.settings.translation.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
