import XCTest
@testable import OtoChefApp

final class WhisperKitModelPathResolverTests: XCTestCase {
    func testRelativeModelFolderResolvesUnderProjectRoot() {
        let resolver = WhisperKitModelPathResolver(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))

        let url = resolver.resolveModelBaseURL("Models/whisperkit")

        XCTAssertEqual(url.path, "/tmp/OtoChef/Models/whisperkit")
    }

    func testAbsoluteModelFolderIsPreserved() {
        let resolver = WhisperKitModelPathResolver(projectRoot: URL(fileURLWithPath: "/tmp/OtoChef", isDirectory: true))

        let url = resolver.resolveModelBaseURL("/Users/example/Models/whisperkit")

        XCTAssertEqual(url.path, "/Users/example/Models/whisperkit")
    }
}
