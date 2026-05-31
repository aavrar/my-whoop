import Foundation

public struct StageSegment: Equatable, Codable {
    public let start: Int
    public let end: Int
    public let stage: String  // "wake" | "light" | "deep" | "rem"

    public init(start: Int, end: Int, stage: String) {
        self.start = start; self.end = end; self.stage = stage
    }
}

public struct ComputedSleepSession: Equatable {
    public let startTs: Int
    public let endTs: Int
    public let efficiency: Double
    public let restingHr: Int?
    public let avgHrv: Double?
    public let stages: [StageSegment]
}

public struct ComputedDailyMetric: Equatable {
    public let day: String
    public let totalSleepMin: Double?
    public let efficiency: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let lightMin: Double?
    public let disturbances: Int?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let recovery: Double?
    public let strain: Double?
}
