import Foundation

struct JobFileWriter {
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func write(_ job: OtoChefJob) throws -> JobArtifacts {
        let outputDirectory = URL(fileURLWithPath: job.outputDirectory, isDirectory: true)
        let safeID = job.id.uuidString.lowercased()
        let workingDirectory = outputDirectory
            .appendingPathComponent(".otochef", isDirectory: true)
            .appendingPathComponent(safeID, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let jobFile = workingDirectory.appendingPathComponent("job.json")
        var jobForWorker = job
        jobForWorker.outputDirectory = outputDirectory.path
        jobForWorker.workingDirectory = workingDirectory.path
        let data = try encoder.encode(jobForWorker)
        try data.write(to: jobFile, options: [.atomic])

        return JobArtifacts(workingDirectory: workingDirectory, jobFile: jobFile)
    }
}
