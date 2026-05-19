import XCTest
@testable import OtoChefApp

final class APIKeyStoreTests: XCTestCase {
    func testMemoryAPIKeyStoreSavesLoadsAndClearsPerProviderKeys() throws {
        let store = MemoryAPIKeyStore()

        try store.saveTranslationAPIKey("deepseek-key", for: .deepSeek)
        try store.saveTranslationAPIKey("openai-key", for: .openAI)

        XCTAssertEqual(try store.loadTranslationAPIKey(for: .deepSeek), "deepseek-key")
        XCTAssertEqual(try store.loadTranslationAPIKey(for: .openAI), "openai-key")

        try store.clearTranslationAPIKey(for: .deepSeek)

        XCTAssertNil(try store.loadTranslationAPIKey(for: .deepSeek))
        XCTAssertEqual(try store.loadTranslationAPIKey(for: .openAI), "openai-key")
    }
}
