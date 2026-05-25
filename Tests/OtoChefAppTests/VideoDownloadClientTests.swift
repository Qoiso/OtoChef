import XCTest
@testable import OtoChefApp

final class VideoDownloadClientTests: XCTestCase {
    func testArgumentsDownloadCompatibleMP4VideoAndAudioIntoOutputDirectory() {
        let request = VideoDownloadRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: "https://example.com/watch?v=abc",
            outputDirectory: URL(fileURLWithPath: "/tmp/downloads", isDirectory: true),
            workingDirectory: URL(fileURLWithPath: "/tmp/downloads/.otochef/video", isDirectory: true),
            preset: .videoAudioMP4,
            ytDLPPath: "/opt/homebrew/bin/yt-dlp"
        )

        let arguments = VideoDownloadClient.arguments(for: request)

        XCTAssertEqual(arguments.first, "--newline")
        XCTAssertTrue(arguments.contains("--restrict-filenames"))
        XCTAssertTrue(arguments.contains("-P"))
        XCTAssertTrue(arguments.contains("/tmp/downloads"))
        XCTAssertTrue(arguments.contains("--merge-output-format"))
        XCTAssertTrue(arguments.contains("--remux-video"))
        XCTAssertTrue(arguments.contains("mp4"))
        XCTAssertTrue(arguments.contains("bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"))
        XCTAssertEqual(arguments.last, "https://example.com/watch?v=abc")
    }

    func testArgumentsDownloadBestVideoAndAudioUsesExplicitFormatSelector() {
        let request = VideoDownloadRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            url: "https://example.com/watch?v=abc",
            outputDirectory: URL(fileURLWithPath: "/tmp/downloads", isDirectory: true),
            workingDirectory: URL(fileURLWithPath: "/tmp/downloads/.otochef/video", isDirectory: true),
            preset: .videoAudioBest,
            ytDLPPath: "/opt/homebrew/bin/yt-dlp"
        )

        let arguments = VideoDownloadClient.arguments(for: request)

        XCTAssertTrue(arguments.contains("bv*+ba/b"))
        XCTAssertFalse(arguments.contains("--merge-output-format"))
    }

    func testArgumentsDownloadVideoOnlyWhenPresetIsVideoOnly() {
        let request = VideoDownloadRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            url: "https://example.com/watch?v=abc",
            outputDirectory: URL(fileURLWithPath: "/tmp/downloads", isDirectory: true),
            workingDirectory: URL(fileURLWithPath: "/tmp/downloads/.otochef/video", isDirectory: true),
            preset: .videoOnlyBest,
            ytDLPPath: "/opt/homebrew/bin/yt-dlp"
        )

        let arguments = VideoDownloadClient.arguments(for: request)

        XCTAssertTrue(arguments.contains("bv*"))
        XCTAssertFalse(arguments.contains("ba/best"))
        XCTAssertFalse(arguments.contains("-x"))
    }

    func testArgumentsExtractM4AAudioWhenPresetIsAudioM4A() {
        let request = VideoDownloadRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            url: "https://example.com/watch?v=abc",
            outputDirectory: URL(fileURLWithPath: "/tmp/downloads", isDirectory: true),
            workingDirectory: URL(fileURLWithPath: "/tmp/downloads/.otochef/video", isDirectory: true),
            preset: .audioM4A,
            ytDLPPath: "/opt/homebrew/bin/yt-dlp"
        )

        let arguments = VideoDownloadClient.arguments(for: request)

        XCTAssertTrue(arguments.contains("-x"))
        XCTAssertTrue(arguments.contains("ba/best"))
        XCTAssertTrue(arguments.contains("--audio-format"))
        XCTAssertTrue(arguments.contains("m4a"))
        XCTAssertTrue(arguments.contains("--audio-quality"))
        XCTAssertTrue(arguments.contains("0"))
    }

    func testPresetDetailsExposeConcreteYtDLPArguments() {
        XCTAssertEqual(VideoDownloadPreset.videoAudioMP4.argumentSummary, "-f bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b --merge-output-format mp4 --remux-video mp4")
        XCTAssertEqual(VideoDownloadPreset.audioMP3.argumentSummary, "-x -f ba/best --audio-format mp3 --audio-quality 0")
    }

    func testProgressParserExtractsPercentLines() {
        var parser = VideoDownloadProgressParser()

        let events = parser.append("noise\notochef-progress: 42.7%\n")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .progress)
        XCTAssertEqual(events.first?.stage, "video_download")
        XCTAssertEqual(try XCTUnwrap(events.first?.progress), 0.427, accuracy: 0.001)
    }
}
