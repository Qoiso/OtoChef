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
}
