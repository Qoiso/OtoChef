import Foundation

enum WorkerEventType: String, Codable, Equatable {
    case jobStarted = "job_started"
    case stageStarted = "stage_started"
    case progress
    case warning
    case artifactCreated = "artifact_created"
    case stageFailed = "stage_failed"
    case jobFinished = "job_finished"
}

struct WorkerEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var type: WorkerEventType
    var stage: String?
    var message: String?
    var progress: Double?
    var path: String?

    enum CodingKeys: String, CodingKey {
        case type
        case stage
        case message
        case progress
        case path
    }
}

struct WorkerEventParser {
    private let decoder = JSONDecoder()

    func parse(_ line: String) throws -> WorkerEvent {
        let data = Data(line.utf8)
        return try decoder.decode(WorkerEvent.self, from: data)
    }
}
