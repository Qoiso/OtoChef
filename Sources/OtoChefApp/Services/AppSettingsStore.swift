import Foundation

protocol AppSettingsStore {
    func load() throws -> AppSettings?
    func save(_ settings: AppSettings) throws
}

final class MemoryAppSettingsStore: AppSettingsStore {
    private var settings: AppSettings?

    func load() throws -> AppSettings? {
        settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}

final class UserDefaultsAppSettingsStore: AppSettingsStore {
    private let defaults: UserDefaults
    private let key = "otochef.app-settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> AppSettings? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
