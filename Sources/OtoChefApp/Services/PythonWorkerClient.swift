import Foundation

protocol PythonWorkerRunning {
    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws
}

final class PythonWorkerClient: PythonWorkerRunning {
    private var runningProcess: Process?

    static func condaArguments(environmentName: String, jobFile: URL) -> [String] {
        [
            "run",
            "--no-capture-output",
            "-n",
            environmentName,
            "python",
            "-m",
            "otochef_worker",
            "--job",
            jobFile.path
        ]
    }

    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.condaPath)
        process.arguments = Self.condaArguments(environmentName: request.environmentName, jobFile: request.jobFile)
        process.currentDirectoryURL = request.workerDirectory
        var environment = ProcessInfo.processInfo.environment
        request.environment.forEach { key, value in
            environment[key] = value
        }
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        var lineBuffer = WorkerEventLineBuffer()
        var sawTerminalEvent = false

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for event in lineBuffer.append(text) {
                if event.type == .jobFinished || event.type == .stageFailed {
                    sawTerminalEvent = true
                }
                onEvent(event)
            }
        }
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            if !sawTerminalEvent {
                if process.terminationStatus == 0 {
                    onEvent(
                        WorkerEvent(
                            type: .jobFinished,
                            stage: nil,
                            message: "Job finished",
                            progress: 1.0,
                            path: nil
                        )
                    )
                } else {
                    onEvent(
                        WorkerEvent(
                            type: .stageFailed,
                            stage: "worker",
                            message: "Worker exited with status \(process.terminationStatus)",
                            progress: nil,
                            path: nil
                        )
                    )
                }
            }
        }

        try process.run()
        runningProcess = process
    }
}

struct WorkerEventLineBuffer {
    private var pending = ""
    private let parser = WorkerEventParser()

    mutating func append(_ text: String) -> [WorkerEvent] {
        pending += text
        var events: [WorkerEvent] = []
        while let newlineRange = pending.range(of: "\n") {
            let line = String(pending[..<newlineRange.lowerBound])
            pending.removeSubrange(pending.startIndex...newlineRange.lowerBound)
            if let event = try? parser.parse(line) {
                events.append(event)
            }
        }
        return events
    }
}
