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

    func testLaunchConfigurationUsesManagedEnvironmentPythonDirectly() {
        let request = WorkerLaunchRequest(
            condaPath: "/opt/homebrew/bin/conda",
            environmentName: "otochef",
            environmentPath: "/tmp/OtoChef/.otochef-runtime/envs/otochef",
            workerDirectory: URL(fileURLWithPath: "/tmp/OtoChef/worker", isDirectory: true),
            jobFile: URL(fileURLWithPath: "/tmp/job.json"),
            environment: [:]
        )

        let configuration = PythonWorkerClient.launchConfiguration(for: request)

        XCTAssertEqual(configuration.executablePath, "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin/python")
        XCTAssertEqual(configuration.arguments, ["-m", "otochef_worker", "--job", "/tmp/job.json"])
    }

    func testWorkerEnvironmentKeepsOnlyAllowlistedParentValuesAndOverrides() {
        let environment = PythonWorkerClient.workerEnvironment(
            base: [
                "PATH": "/usr/bin",
                "HOME": "/Users/example",
                "AWS_SECRET_ACCESS_KEY": "secret",
                "OTOCHEF_TRANSLATION_API_KEY": "old"
            ],
            overrides: ["OTOCHEF_TRANSLATION_API_KEY": "new"]
        )

        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["HOME"], "/Users/example")
        XCTAssertEqual(environment["OTOCHEF_TRANSLATION_API_KEY"], "new")
        XCTAssertNil(environment["AWS_SECRET_ACCESS_KEY"])
    }

    func testWorkerEnvironmentPrependsManagedEnvironmentBinOnlyForChildProcess() {
        let environment = PythonWorkerClient.workerEnvironment(
            base: ["PATH": "/usr/bin"],
            overrides: [:],
            executableDirectory: "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin"
        )

        XCTAssertEqual(environment["PATH"], "/tmp/OtoChef/.otochef-runtime/envs/otochef/bin:/usr/bin")
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
