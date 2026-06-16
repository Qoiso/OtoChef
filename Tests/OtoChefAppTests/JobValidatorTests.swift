import XCTest
@testable import OtoChefApp

final class JobValidatorTests: XCTestCase {
    func testValidationFailsWhenAudioIsMissing() {
        let draft = JobDraft(
            inputKind: .audio,
            audioURL: nil,
            videoURL: nil,
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: .defaults
        )

        let errors = JobValidator(fileExists: { _ in true }).validate(draft)

        XCTAssertEqual(errors, [.missingAudio])
    }

    func testValidationFailsWhenSelectedPathsDoNotExist() {
        let draft = JobDraft(
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
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

    func testManagedEnvironmentPythonDoesNotRequireExternalConda() {
        var settings = AppSettings.defaults
        settings.conda.executablePath = ""
        settings.conda.environmentName = ""
        settings.conda.environmentPath = "/tmp/OtoChef/.otochef-runtime/envs/otochef"
        let draft = JobDraft(
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
            imageURL: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator(fileExists: { path in
            path == "/tmp/audio.wav"
                || path == "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin/python"
        }).validate(draft)

        XCTAssertFalse(errors.contains(.missingCondaExecutable))
        XCTAssertFalse(errors.contains(.missingCondaEnvironment))
    }

    func testValidationFailsWhenVideoInputsDoNotExistForVideoOutput() {
        var settings = AppSettings.defaults
        settings.video.outputFiles = [.video]
        let draft = JobDraft(
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
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
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
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
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
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
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
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
            inputKind: .audio,
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            videoURL: nil,
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator().validate(draft)

        XCTAssertTrue(errors.contains(.missingTranslationModel))
    }

    func testVideoValidationRequiresVideoInputButNotStaticImage() {
        var settings = AppSettings.defaults
        settings.localizedVideo.outputFiles = [.video]
        let draft = JobDraft(
            inputKind: .video,
            audioURL: nil,
            videoURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            imageURL: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator(fileExists: { $0 != "/tmp/source.mp4" }).validate(draft)

        XCTAssertTrue(errors.contains(.missingVideo))
        XCTAssertFalse(errors.contains(.missingAudio))
        XCTAssertFalse(errors.contains(.missingImage))
    }

    func testVideoValidationUsesLocalizedVideoOutputSettings() {
        var settings = AppSettings.defaults
        settings.video.outputFiles = [.chineseSubtitles]
        settings.localizedVideo.outputFiles = []
        let draft = JobDraft(
            inputKind: .video,
            audioURL: nil,
            videoURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            imageURL: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator(fileExists: { _ in true }).validate(draft)

        XCTAssertTrue(errors.contains(.missingOutputFile))
    }
}
