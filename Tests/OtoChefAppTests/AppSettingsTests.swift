import XCTest
@testable import OtoChefApp

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsUseFasterWhisperAndSystranLargeV3() throws {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.asr.backend, .fasterWhisper)
        XCTAssertEqual(settings.asr.model, "Systran/faster-whisper-large-v3")
        XCTAssertEqual(settings.asr.device, "cpu")
        XCTAssertEqual(settings.asr.computeType, "int8")
        XCTAssertEqual(settings.asr.beamSize, 1)
        XCTAssertEqual(settings.asr.cpuThreads, 8)
        XCTAssertEqual(settings.conda.environmentName, "otochef")
        XCTAssertEqual(settings.video.width, 1920)
        XCTAssertEqual(settings.video.height, 1080)
    }

    func testToolSettingsPreferFFmpegFullWhenAvailable() {
        let path = ToolSettings.defaultFFmpegPath(fileExists: { $0 == ToolSettings.ffmpegFullPath })

        XCTAssertEqual(path, ToolSettings.ffmpegFullPath)
    }

    func testToolSettingsFallbackToHomebrewFFmpegWhenFFmpegFullIsMissing() {
        let path = ToolSettings.defaultFFmpegPath(fileExists: { _ in false })

        XCTAssertEqual(path, ToolSettings.homebrewFFmpegPath)
    }

    func testResolvingToolDefaultsMigratesOldDefaultFFmpegPathToFFmpegFull() {
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = ToolSettings.homebrewFFmpegPath

        let resolved = settings.resolvingAvailableToolDefaults(fileExists: { $0 == ToolSettings.ffmpegFullPath })

        XCTAssertEqual(resolved.tools.ffmpegPath, ToolSettings.ffmpegFullPath)
    }

    func testResolvingToolDefaultsPreservesCustomFFmpegPath() {
        var settings = AppSettings.defaults
        settings.tools.ffmpegPath = "/custom/bin/ffmpeg"

        let resolved = settings.resolvingAvailableToolDefaults(fileExists: { $0 == ToolSettings.ffmpegFullPath })

        XCTAssertEqual(resolved.tools.ffmpegPath, "/custom/bin/ffmpeg")
    }

    func testASRSettingsDecodeDefaultsCPUThreadsForOlderSavedSettings() throws {
        let json = """
        {
          "backend": "fasterWhisper",
          "model": "Systran/faster-whisper-large-v3",
          "device": "cpu",
          "computeType": "int8",
          "language": "ja",
          "vadEnabled": true,
          "beamSize": 1
        }
        """

        let settings = try JSONDecoder().decode(ASRSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.cpuThreads, 8)
    }
}
