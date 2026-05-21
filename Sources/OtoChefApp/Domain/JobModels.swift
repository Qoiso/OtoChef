import Foundation

struct JobDraft: Equatable {
    var audioURL: URL?
    var imageURL: URL?
    var outputDirectory: URL?
    var settings: AppSettings
}

struct OtoChefJob: Codable, Equatable {
    var id: UUID
    var audioPath: String
    var imagePath: String
    var outputDirectory: String
    var workingDirectory: String?
    var settings: AppSettings
    var createdAt: Date
}

enum JobSubmissionMode: String, Codable, Equatable {
    case parallel
    case queued

    var label: String {
        switch self {
        case .parallel:
            return "并行"
        case .queued:
            return "排队"
        }
    }
}

enum RecentJobStatus: String, Codable, Equatable {
    case queued
    case running
    case finished
    case failed

    var label: String {
        switch self {
        case .queued:
            return "等待中"
        case .running:
            return "处理中"
        case .finished:
            return "已完成"
        case .failed:
            return "失败"
        }
    }
}

struct RecentJob: Codable, Equatable, Identifiable {
    var id: UUID
    var audioPath: String
    var imagePath: String
    var outputDirectory: String
    var workingDirectory: String
    var translationProvider: TranslationProvider
    var createdAt: Date
    var status: RecentJobStatus
    var statusMessage: String
    var progress: Double? = nil
    var submissionMode: JobSubmissionMode? = nil
}

enum JobValidationError: String, Equatable, Identifiable {
    case missingAudio
    case missingImage
    case missingOutputDirectory
    case missingOutputFile
    case missingASRModel
    case missingCondaExecutable
    case missingCondaEnvironment
    case missingFFmpeg
    case missingTranslationEndpoint
    case missingTranslationModel

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingAudio:
            return "请选择日语音频文件。"
        case .missingImage:
            return "请选择静态图片。"
        case .missingOutputDirectory:
            return "请选择输出文件夹。"
        case .missingOutputFile:
            return "请至少选择一个输出文件。"
        case .missingASRModel:
            return "请填写 WhisperKit 模型名称。"
        case .missingCondaExecutable:
            return "请配置 conda 可执行文件路径。"
        case .missingCondaEnvironment:
            return "请配置 conda 环境名。"
        case .missingFFmpeg:
            return "请配置 FFmpeg 可执行文件路径。"
        case .missingTranslationEndpoint:
            return "请配置翻译服务地址。"
        case .missingTranslationModel:
            return "请配置翻译模型名称。"
        }
    }
}

struct JobArtifacts: Equatable {
    var workingDirectory: URL
    var jobFile: URL
}

struct WorkerLaunchRequest: Equatable {
    var condaPath: String
    var environmentName: String
    var workerDirectory: URL
    var jobFile: URL
    var environment: [String: String]
}
