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

        let errors = JobValidator().validate(draft)

        XCTAssertEqual(errors, [.missingAudio])
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
