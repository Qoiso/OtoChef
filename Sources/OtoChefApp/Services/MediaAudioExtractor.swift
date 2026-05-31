import Foundation

protocol MediaAudioExtracting {
    func extractAudio(from videoURL: URL, to audioURL: URL, ffmpegPath: String) throws
}

struct FFmpegMediaAudioExtractor: MediaAudioExtracting {
    func extractAudio(from videoURL: URL, to audioURL: URL, ffmpegPath: String) throws {
        try FileManager.default.createDirectory(
            at: audioURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-y",
            "-i", videoURL.path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            audioURL.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "OtoChef.FFmpegMediaAudioExtractor",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "视频音频提取失败：\(details.suffix(800))"]
            )
        }
    }
}
