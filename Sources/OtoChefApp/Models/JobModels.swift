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
    var settings: AppSettings
    var createdAt: Date
}

enum JobValidationError: String, Equatable, Identifiable {
    case missingAudio
    case missingImage
    case missingOutputDirectory
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
        case .missingASRModel:
            return "请填写 faster-whisper 模型路径或模型 ID。"
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

