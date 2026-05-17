import XCTest
@testable import OtoChefApp

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsUseFasterWhisperAndSystranLargeV3() throws {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.asr.backend, .fasterWhisper)
        XCTAssertEqual(settings.asr.model, "Systran/faster-whisper-large-v3")
        XCTAssertEqual(settings.conda.environmentName, "otochef")
        XCTAssertEqual(settings.video.width, 1920)
        XCTAssertEqual(settings.video.height, 1080)
    }
}
