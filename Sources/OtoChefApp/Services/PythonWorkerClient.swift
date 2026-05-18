import Foundation

final class PythonWorkerClient {
    private let parser = WorkerEventParser()
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

        outputPipe.fileHandleForReading.readabilityHandler = { [parser] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for line in text.split(separator: "\n") {
                if let event = try? parser.parse(String(line)) {
                    onEvent(event)
                }
            }
        }

        try process.run()
        runningProcess = process
    }
}
