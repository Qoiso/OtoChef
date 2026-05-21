import XCTest
@testable import OtoChefApp

final class JobValidatorTests: XCTestCase {
    func testValidationFailsWhenAudioIsMissing() {
        let draft = JobDraft(
            audioURL: nil,
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: .defaults
        )

        let errors = JobValidator(fileExists: { _ in true }).validate(draft)

        XCTAssertEqual(errors, [.missingAudio])
    }

    func testValidationFailsWhenSelectedPathsDoNotExist() {
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: .defaults
        )

        let errors = JobValidator(fileExists: { _ in false }).validate(draft)

        XCTAssertTrue(errors.contains(.missingAudio))
        XCTAssertTrue(errors.contains(.missingCondaExecutable))
        XCTAssertFalse(errors.contains(.missingImage))
        XCTAssertFalse(errors.contains(.missingOutputDirectory))
        XCTAssertFalse(errors.contains(.missingFFmpeg))
    }

    func testValidationFailsWhenVideoInputsDoNotExistForVideoOutput() {
        var settings = AppSettings.defaults
        settings.video.outputFiles = [.video]
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator(fileExists: { _ in false }).validate(draft)

        XCTAssertTrue(errors.contains(.missingImage))
        XCTAssertTrue(errors.contains(.missingFFmpeg))
    }

    func testValidationFailsWhenNoOutputFileIsSelected() {
        var settings = AppSettings.defaults
        settings.video.outputFiles = []
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator(fileExists: { _ in true }).validate(draft)

        XCTAssertTrue(errors.contains(.missingOutputFile))
    }

    func testJapaneseSubtitleOnlyDoesNotRequireTranslationConfiguration() {
        var settings = AppSettings.defaults
        settings.video.outputFiles = [.japaneseSubtitles]
        settings.translation.updateConfiguration(for: .ollama) { configuration in
            configuration.baseURL = ""
            configuration.model = ""
        }
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator(fileExists: { _ in true }).validate(draft)

        XCTAssertFalse(errors.contains(.missingTranslationEndpoint))
        XCTAssertFalse(errors.contains(.missingTranslationModel))
    }

    func testValidationFailsWhenTranslationEndpointIsEmpty() {
        var settings = AppSettings.defaults
        settings.translation.selectedProvider = .deepSeek
        settings.translation.updateConfiguration(for: .deepSeek) { configuration in
            configuration.baseURL = ""
        }
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator().validate(draft)

        XCTAssertTrue(errors.contains(.missingTranslationEndpoint))
    }

    func testValidationFailsWhenSelectedProviderModelIsEmpty() {
        var settings = AppSettings.defaults
        settings.translation.selectedProvider = .claude
        settings.translation.updateConfiguration(for: .claude) { configuration in
            configuration.model = ""
        }
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator().validate(draft)

        XCTAssertTrue(errors.contains(.missingTranslationModel))
    }
}
