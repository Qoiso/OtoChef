import XCTest
@testable import OtoChefApp

final class WorkerEventParserTests: XCTestCase {
    func testParsesStageStartedEvent() throws {
        let line = #"{"type":"stage_started","stage":"asr","message":"Transcribing audio"}"#

        let event = try WorkerEventParser().parse(line)

        XCTAssertEqual(event.type, .stageStarted)
        XCTAssertEqual(event.stage, "asr")
        XCTAssertEqual(event.message, "Transcribing audio")
    }

    func testParsesArtifactEvent() throws {
        let line = #"{"type":"artifact_created","stage":"subtitle","path":"/tmp/subtitles.zh.ass"}"#

        let event = try WorkerEventParser().parse(line)

        XCTAssertEqual(event.type, .artifactCreated)
        XCTAssertEqual(event.path, "/tmp/subtitles.zh.ass")
    }
}
