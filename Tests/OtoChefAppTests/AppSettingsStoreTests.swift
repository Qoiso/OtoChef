import XCTest
@testable import OtoChefApp

final class AppSettingsStoreTests: XCTestCase {
    func testMemorySettingsStorePersistsChangedTranslationAndASRSettings() throws {
        let store = MemoryAppSettingsStore()
        var settings = AppSettings.defaults
        settings.asr.beamSize = 3
        settings.translation.updateConfiguration(for: .openAICompatible) { configuration in
            configuration.baseURL = "https://api.example.com/v1"
            configuration.model = "example-model"
        }
        settings.translation.prompt = "Translate carefully"

        try store.save(settings)

        XCTAssertEqual(try store.load()?.asr.beamSize, 3)
        XCTAssertEqual(try store.load()?.translation.configuration(for: .openAICompatible).baseURL, "https://api.example.com/v1")
        XCTAssertEqual(try store.load()?.translation.configuration(for: .openAICompatible).model, "example-model")
        XCTAssertEqual(try store.load()?.translation.prompt, "Translate carefully")
    }
}
