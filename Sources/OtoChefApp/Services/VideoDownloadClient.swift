import Foundation

protocol VideoDownloadRunning {
    func run(_ request: VideoDownloadRequest, onEvent: @escaping (WorkerEvent) -> Void) throws
}

final class VideoDownloadClient: VideoDownloadRunning {
    private let processLock = NSLock()
    private var runningProcesses: [Process] = []

    static func arguments(for request: VideoDownloadRequest) -> [String] {
        var arguments = [
            "--newline",
            "--restrict-filenames",
            "-P",
            request.outputDirectory.path,
            "-o",
            "%(title).180B-%(id)s.%(ext)s",
            "--progress-template",
            "download:otochef-progress:%(progress._percent_str)s",
            "--print",
            "after_move:otochef-file:%(filepath)s"
        ]

        arguments.append(contentsOf: request.preset.arguments)
        if request.preset.isMP4Remux {
            arguments.append(contentsOf: ["--merge-output-format", "mp4", "--remux-video", "mp4"])
        }

        arguments.append(request.url)
        return arguments
    }

    func run(_ request: VideoDownloadRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: request.workingDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.ytDLPPath)
        process.arguments = Self.arguments(for: request)
        process.currentDirectoryURL = request.outputDirectory
        process.environment = Self.downloadEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        var parser = VideoDownloadProgressParser()
        var sawTerminalEvent = false

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for event in parser.append(text) {
                if event.type == .jobFinished || event.type == .stageFailed {
                    sawTerminalEvent = true
                }
                onEvent(event)
            }
        }
        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            if !sawTerminalEvent {
                if process.terminationStatus == 0 {
                    onEvent(
                        WorkerEvent(
                            type: .jobFinished,
                            stage: "video_download",
                            message: "下载完成",
                            progress: 1.0,
                            path: nil
                        )
                    )
                } else {
                    onEvent(
                        WorkerEvent(
                            type: .stageFailed,
                            stage: "video_download",
                            message: "yt-dlp 退出，状态码 \(process.terminationStatus)",
                            progress: nil,
                            path: nil
                        )
                    )
                }
            }
            self?.release(process)
        }

        retain(process)
        onEvent(
            WorkerEvent(
                type: .stageStarted,
                stage: "video_download",
                message: "正在下载视频",
                progress: 0,
                path: nil
            )
        )
        do {
            try process.run()
        } catch {
            release(process)
            throw error
        }
    }

    private static func downloadEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment: [String: String] = [:]
        for key in ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE"] {
            if let value = base[key] {
                environment[key] = value
            }
        }
        return environment
    }

    private func retain(_ process: Process) {
        processLock.lock()
        runningProcesses.append(process)
        processLock.unlock()
    }

    private func release(_ process: Process) {
        processLock.lock()
        runningProcesses.removeAll { $0 === process }
        processLock.unlock()
    }
}

private extension VideoDownloadPreset {
    var arguments: [String] {
        switch self {
        case .videoAudioMP4:
            return ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"]
        case .videoAudioBest:
            return ["-f", "bv*+ba/b"]
        case .videoAudioMP41080p:
            return [
                "-f",
                "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/bv*[height<=1080]+ba/b[height<=1080]"
            ]
        case .videoAudioMP4720p:
            return [
                "-f",
                "bv*[height<=720][ext=mp4]+ba[ext=m4a]/b[height<=720][ext=mp4]/bv*[height<=720]+ba/b[height<=720]"
            ]
        case .videoOnlyBest:
            return ["-f", "bv*"]
        case .videoOnly1080p:
            return ["-f", "bv*[height<=1080]"]
        case .audioM4A:
            return ["-x", "-f", "ba/best", "--audio-format", "m4a", "--audio-quality", "0"]
        case .audioMP3:
            return ["-x", "-f", "ba/best", "--audio-format", "mp3", "--audio-quality", "0"]
        case .audioOpus:
            return ["-x", "-f", "ba/best", "--audio-format", "opus", "--audio-quality", "0"]
        }
    }

    var isMP4Remux: Bool {
        switch self {
        case .videoAudioMP4, .videoAudioMP41080p, .videoAudioMP4720p:
            return true
        case .videoAudioBest, .videoOnlyBest, .videoOnly1080p, .audioM4A, .audioMP3, .audioOpus:
            return false
        }
    }
}

struct VideoDownloadProgressParser {
    private var pending = ""

    mutating func append(_ text: String) -> [WorkerEvent] {
        pending += text
        var events: [WorkerEvent] = []
        while let newlineRange = pending.range(of: "\n") {
            let line = String(pending[..<newlineRange.lowerBound])
            pending.removeSubrange(pending.startIndex...newlineRange.lowerBound)
            if let event = parse(line) {
                events.append(event)
            }
        }
        return events
    }

    private func parse(_ line: String) -> WorkerEvent? {
        if line.hasPrefix("otochef-progress:") {
            let rawPercent = line
                .replacingOccurrences(of: "otochef-progress:", with: "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let percent = Double(rawPercent) else {
                return nil
            }
            return WorkerEvent(
                type: .progress,
                stage: "video_download",
                message: "正在下载视频",
                progress: min(max(percent / 100, 0), 1),
                path: nil
            )
        }

        if line.hasPrefix("otochef-file:") {
            let path = line
                .replacingOccurrences(of: "otochef-file:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkerEvent(
                type: .artifactCreated,
                stage: "video_download",
                message: "已保存下载文件",
                progress: 1.0,
                path: path.isEmpty ? nil : path
            )
        }

        return nil
    }
}
