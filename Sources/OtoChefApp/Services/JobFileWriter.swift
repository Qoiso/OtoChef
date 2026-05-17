import Foundation

struct JobFileWriter {
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func write(_ job: OtoChefJob) throws -> JobArtifacts {
        let safeID = job.id.uuidString.lowercased()
        let workingDirectory = URL(fileURLWithPath: job.outputDirectory)
            .appendingPathComponent("otochef-\(safeID)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let jobFile = workingDirectory.appendingPathComponent("job.json")
        var jobForWorker = job
        jobForWorker.outputDirectory = workingDirectory.path
        let data = try encoder.encode(jobForWorker)
        try data.write(to: jobFile, options: [.atomic])

        return JobArtifacts(workingDirectory: workingDirectory, jobFile: jobFile)
    }
}

