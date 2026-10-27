import Foundation

public struct DiarySettings: Codable, Equatable {
    public var enabled = false
    public var windowInterval: TimeInterval = 600
    public var dwell: TimeInterval = 60
    public var retentionDays: Int? = 30
    public var failedFrameTTL: TimeInterval = 24 * 60 * 60
    public var dailyReportTime = "22:00"
    public var userExcludedBundleIDs: Set<String> = []

    public init() {}

    public func save(to defaults: UserDefaults, key: String = "yijiangDiary.settings") throws {
        try validate()
        defaults.set(try JSONEncoder().encode(self), forKey: key)
    }

    public static func load(from defaults: UserDefaults, key: String = "yijiangDiary.settings") throws -> Self {
        guard let data = defaults.data(forKey: key) else { return Self() }
        let settings = try JSONDecoder().decode(Self.self, from: data)
        try settings.validate()
        return settings
    }

    public func validate() throws {
        let time = dailyReportTime.split(separator: ":", omittingEmptySubsequences: false)
        guard windowInterval.isFinite, windowInterval > 0, dwell.isFinite, dwell >= 0,
              failedFrameTTL.isFinite, failedFrameTTL >= 0,
              retentionDays == nil || [7, 30, 90].contains(retentionDays!),
              time.count == 2, time.allSatisfy({ $0.count == 2 }),
              let hour = Int(time[0]), let minute = Int(time[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { throw DiarySettingsError.invalidSettings }
    }
}

public enum DiarySettingsError: Error { case invalidSettings }
