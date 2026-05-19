import XCTest
@testable import OtoChefApp

final class PythonWorkerClientTests: XCTestCase {
    func testCondaArgumentsDisableOutputCapture() {
        let jobFile = URL(fileURLWithPath: "/tmp/job.json")

        let arguments = PythonWorkerClient.condaArguments(environmentName: "otochef", jobFile: jobFile)

        XCTAssertEqual(arguments.prefix(3), ["run", "--no-capture-output", "-n"])
        XCTAssertTrue(arguments.contains("--job"))
        XCTAssertEqual(arguments.last, "/tmp/job.json")
    }

    func testWorkerEventLineBufferPreservesSplitJSONLines() throws {
        var buffer = WorkerEventLineBuffer()

        XCTAssertTrue(buffer.append("{\"type\":\"stage_started\",\"stage\":\"translation\"").isEmpty)
        let events = buffer.append(",\"message\":\"正在翻译中文字幕\",\"progress\":0.45}\n")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .stageStarted)
        XCTAssertEqual(events.first?.stage, "translation")
    }

    func testWorkerEventLineBufferSkipsNonJSONLinesAndKeepsFollowingEvents() throws {
        var buffer = WorkerEventLineBuffer()

        let events = buffer.append(
            "ffmpeg version 7.0\n{\"type\":\"job_finished\",\"message\":\"Job finished\"}\n"
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .jobFinished)
    }
}
