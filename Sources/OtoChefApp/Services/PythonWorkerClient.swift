import Foundation

protocol PythonWorkerRunning {
    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws
}

final class PythonWorkerClient: PythonWorkerRunning {
    struct LaunchConfiguration: Equatable {
        var executablePath: String
        var arguments: [String]
    }

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

    static func launchConfiguration(for request: WorkerLaunchRequest) -> LaunchConfiguration {
        if let environmentPath = request.environmentPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentPath.isEmpty {
            return LaunchConfiguration(
                executablePath: URL(fileURLWithPath: environmentPath, isDirectory: true)
                    .appendingPathComponent("bin/python")
                    .path,
                arguments: ["-m", "otochef_worker", "--job", request.jobFile.path]
            )
        }
        return LaunchConfiguration(
            executablePath: request.condaPath,
            arguments: condaArguments(environmentName: request.environmentName, jobFile: request.jobFile)
        )
    }

    static func workerEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        overrides: [String: String],
        executableDirectory: String? = nil
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
        if let executableDirectory, !executableDirectory.isEmpty {
            let inheritedPath = environment["PATH"] ?? ""
            environment["PATH"] = inheritedPath.isEmpty
                ? executableDirectory
                : "\(executableDirectory):\(inheritedPath)"
        }
        return environment
    }

    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        let launchConfiguration = Self.launchConfiguration(for: request)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchConfiguration.executablePath)
        process.arguments = launchConfiguration.arguments
        process.currentDirectoryURL = request.workerDirectory
        process.environment = Self.workerEnvironment(
            overrides: request.environment,
            executableDirectory: URL(fileURLWithPath: launchConfiguration.executablePath)
                .deletingLastPathComponent()
                .path
        )

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
