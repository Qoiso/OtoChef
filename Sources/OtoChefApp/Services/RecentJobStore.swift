import Foundation

protocol RecentJobStore {
    func load() throws -> [RecentJob]
    func save(_ jobs: [RecentJob]) throws
}

final class MemoryRecentJobStore: RecentJobStore {
    private var jobs: [RecentJob] = []

    func load() throws -> [RecentJob] {
        jobs
    }

    func save(_ jobs: [RecentJob]) throws {
        self.jobs = jobs
    }
}

final class UserDefaultsRecentJobStore: RecentJobStore {
    private let defaults: UserDefaults
    private let key = "otochef.recent-jobs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> [RecentJob] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return try JSONDecoder().decode([RecentJob].self, from: data)
    }

    func save(_ jobs: [RecentJob]) throws {
        let data = try JSONEncoder().encode(jobs)
        defaults.set(data, forKey: key)
    }
}
