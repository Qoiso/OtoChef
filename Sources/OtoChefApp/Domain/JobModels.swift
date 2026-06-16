import Foundation

enum JobInputKind: String, Codable, Equatable {
    case audio
    case video
}

struct JobDraft: Equatable {
    var inputKind: JobInputKind = .audio
    var audioURL: URL?
    var videoURL: URL?
    var imageURL: URL?
    var outputDirectory: URL?
    var settings: AppSettings
}

struct VideoDownloadDraft: Equatable {
    var urlString: String
    var outputDirectory: URL?
}

struct OtoChefJob: Codable, Equatable {
    var id: UUID
    var inputKind: JobInputKind
    var audioPath: String
    var videoPath: String?
    var imagePath: String
    var outputDirectory: String
    var workingDirectory: String?
    var settings: AppSettings
    var createdAt: Date
}

enum VideoDownloadPreset: String, Codable, Equatable, CaseIterable, Identifiable {
    case videoAudioMP4
    case videoAudioBest
    case videoAudioMP41080p
    case videoAudioMP4720p
    case videoOnlyBest
    case videoOnly1080p
    case audioM4A
    case audioMP3
    case audioOpus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .videoAudioMP4:
            return "视频+音频，兼容 MP4"
        case .videoAudioBest:
            return "视频+音频，自动最佳"
        case .videoAudioMP41080p:
            return "视频+音频，MP4，最高 1080p"
        case .videoAudioMP4720p:
            return "视频+音频，MP4，最高 720p"
        case .videoOnlyBest:
            return "仅视频轨，自动最佳"
        case .videoOnly1080p:
            return "仅视频轨，最高 1080p"
        case .audioM4A:
            return "仅音频，M4A"
        case .audioMP3:
            return "仅音频，MP3"
        case .audioOpus:
            return "仅音频，Opus"
        }
    }

    var argumentSummary: String {
        switch self {
        case .videoAudioMP4:
            return "-f bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b --merge-output-format mp4 --remux-video mp4"
        case .videoAudioBest:
            return "-f bv*+ba/b"
        case .videoAudioMP41080p:
            return "-f bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/bv*[height<=1080]+ba/b[height<=1080] --merge-output-format mp4 --remux-video mp4"
        case .videoAudioMP4720p:
            return "-f bv*[height<=720][ext=mp4]+ba[ext=m4a]/b[height<=720][ext=mp4]/bv*[height<=720]+ba/b[height<=720] --merge-output-format mp4 --remux-video mp4"
        case .videoOnlyBest:
            return "-f bv*"
        case .videoOnly1080p:
            return "-f bv*[height<=1080]"
        case .audioM4A:
            return "-x -f ba/best --audio-format m4a --audio-quality 0"
        case .audioMP3:
            return "-x -f ba/best --audio-format mp3 --audio-quality 0"
        case .audioOpus:
            return "-x -f ba/best --audio-format opus --audio-quality 0"
        }
    }
}

struct VideoDownloadRequest: Equatable {
    var id: UUID
    var url: String
    var outputDirectory: URL
    var workingDirectory: URL
    var preset: VideoDownloadPreset
    var ytDLPPath: String
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

enum RecentJobKind: String, Codable, Equatable {
    case audio
    case video
    case videoDownload

    var label: String {
        switch self {
        case .audio:
            return "音声"
        case .video:
            return "视频"
        case .videoDownload:
            return "视频下载"
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
    var kind: RecentJobKind = .audio
    var videoURL: String? = nil
    var downloadedFilePath: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case audioPath
        case imagePath
        case outputDirectory
        case workingDirectory
        case translationProvider
        case createdAt
        case status
        case statusMessage
        case progress
        case submissionMode
        case kind
        case videoURL
        case downloadedFilePath
    }

    init(
        id: UUID,
        audioPath: String,
        imagePath: String,
        outputDirectory: String,
        workingDirectory: String,
        translationProvider: TranslationProvider,
        createdAt: Date,
        status: RecentJobStatus,
        statusMessage: String,
        progress: Double? = nil,
        submissionMode: JobSubmissionMode? = nil,
        kind: RecentJobKind = .audio,
        videoURL: String? = nil,
        downloadedFilePath: String? = nil
    ) {
        self.id = id
        self.audioPath = audioPath
        self.imagePath = imagePath
        self.outputDirectory = outputDirectory
        self.workingDirectory = workingDirectory
        self.translationProvider = translationProvider
        self.createdAt = createdAt
        self.status = status
        self.statusMessage = statusMessage
        self.progress = progress
        self.submissionMode = submissionMode
        self.kind = kind
        self.videoURL = videoURL
        self.downloadedFilePath = downloadedFilePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        audioPath = try container.decode(String.self, forKey: .audioPath)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        outputDirectory = try container.decode(String.self, forKey: .outputDirectory)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        translationProvider = try container.decode(TranslationProvider.self, forKey: .translationProvider)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(RecentJobStatus.self, forKey: .status)
        statusMessage = try container.decode(String.self, forKey: .statusMessage)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        submissionMode = try container.decodeIfPresent(JobSubmissionMode.self, forKey: .submissionMode)
        kind = try container.decodeIfPresent(RecentJobKind.self, forKey: .kind) ?? .audio
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
        downloadedFilePath = try container.decodeIfPresent(String.self, forKey: .downloadedFilePath)
    }
}

enum JobValidationError: String, Equatable, Identifiable {
    case missingAudio
    case missingVideo
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
        case .missingVideo:
            return "请选择视频文件。"
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

enum VideoDownloadValidationError: String, Error, Equatable, Identifiable {
    case missingURL
    case invalidURL
    case missingOutputDirectory
    case missingYtDLP

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingURL:
            return "请输入视频链接。"
        case .invalidURL:
            return "请输入有效的视频链接。"
        case .missingOutputDirectory:
            return "请选择下载输出文件夹。"
        case .missingYtDLP:
            return "请配置 yt-dlp 可执行文件路径。"
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
    var environmentPath: String?
    var workerDirectory: URL
    var jobFile: URL
    var environment: [String: String]
}
