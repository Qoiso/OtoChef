import Foundation

protocol PythonWorkerRunning {
    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws
}

final class PythonWorkerClient: PythonWorkerRunning {
    private let processLock = NSLock()
    private var runningProcesses: [Process] = []
    private static let inheritedEnvironmentKeys = [
        "PATH",
        "HOME",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "SSL_CERT_FILE",
        "REQUESTS_CA_BUNDLE"
    ]

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

    static func workerEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        overrides: [String: String]
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for key in inheritedEnvironmentKeys {
            if let value = base[key] {
                environment[key] = value
            }
        }
        overrides.forEach { key, value in
            environment[key] = value
        }
        return environment
    }

    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.condaPath)
        process.arguments = Self.condaArguments(environmentName: request.environmentName, jobFile: request.jobFile)
        process.currentDirectoryURL = request.workerDirectory
        process.environment = Self.workerEnvironment(overrides: request.environment)

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
        process.terminationHandler = { [weak self] process in
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
            self?.release(process)
        }

        retain(process)
        do {
            try process.run()
        } catch {
            release(process)
            throw error
        }
    }

    private func retain(_ process: Process) {
        processLock.lock()
        runningProcesses.append(process)
        processLock.unlock()
    }

    private func release(_ process: Process) {
        processLock.lock()
        runningProcesses.removeAll { $0 === process }
        processLock.unlock()
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
