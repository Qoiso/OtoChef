import XCTest
@testable import OtoChefApp

final class APIKeyStoreTests: XCTestCase {
    func testMemoryAPIKeyStoreSavesAndLoadsTranslationKey() throws {
        let store = MemoryAPIKeyStore()

        try store.saveTranslationAPIKey("test-key")

        XCTAssertEqual(try store.loadTranslationAPIKey(), "test-key")
    }
}
