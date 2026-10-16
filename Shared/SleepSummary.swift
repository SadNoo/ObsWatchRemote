import SwiftUI

/// 一段睡眠记录（与 HealthKit 解耦，方便在两端共用和计算）。
struct SleepSegment {
    enum Stage { case inBed, awake, core, deep, rem, unspecified }

    var stage: Stage
    var start: Date
    var end: Date
    var source: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var isAsleep: Bool { [.core, .deep, .rem, .unspecified].contains(stage) }
}

/// 昨晚的睡眠概况和评分。
struct SleepSummary: Codable, Equatable {
    enum Level: String, Codable {
        case excellent, good, fair, poor

        init(score: Int) {
            switch score {
            case 85...: self = .excellent
            case 70..<85: self = .good
            case 55..<70: self = .fair
            default: self = .poor
            }
        }

        var label: String {
            switch self {
            case .excellent: return "状态极佳"
            case .good: return "状态不错"
            case .fair: return "状态一般"
            case .poor: return "需要休息"
            }
        }

        var emoji: String {
            switch self {
            case .excellent: return "🌟"
            case .good: return "😊"
            case .fair: return "😐"
            case .poor: return "😴"
            }
        }
    }

    var bedtime: Date
    var wakeTime: Date
    var asleep: TimeInterval
    var deep: TimeInterval
    var rem: TimeInterval
    var core: TimeInterval
    var awake: TimeInterval
    var hasStages: Bool
    var score: Int
    var level: Level

    var deepPercent: Double { asleep > 0 ? deep / asleep * 100 : 0 }
    var remPercent: Double { asleep > 0 ? rem / asleep * 100 : 0 }
    /// 睡着时间 / 从入睡到醒来的总时长
    var efficiency: Double {
        let span = wakeTime.timeIntervalSince(bedtime)
        return span > 0 ? min(1, asleep / span) : 0
    }

    /// 从一晚的所有记录生成概况；没有睡眠数据时返回 nil。
    /// 多个来源（手表、iPhone、第三方 App）可能重复记录，只取睡眠时长最多的那个来源。
    static func make(from segments: [SleepSegment]) -> SleepSummary? {
        let bySource = Dictionary(grouping: segments.filter { $0.stage != .inBed }, by: \.source)
        guard let best = bySource.values.max(by: { asleepTime($0) < asleepTime($1) }) else { return nil }

        let asleep = asleepTime(best)
        guard asleep > 0,
              let bedtime = best.filter(\.isAsleep).map(\.start).min(),
              let wakeTime = best.filter(\.isAsleep).map(\.end).max()
        else { return nil }

        func total(_ stage: SleepSegment.Stage) -> TimeInterval {
            best.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
        }

        let deep = total(.deep), rem = total(.rem), core = total(.core)
        let hasStages = deep + rem + core > 0
        let score = Self.score(
            asleep: asleep, deep: deep, rem: rem,
            span: wakeTime.timeIntervalSince(bedtime), hasStages: hasStages
        )
        return SleepSummary(
            bedtime: bedtime, wakeTime: wakeTime, asleep: asleep,
            deep: deep, rem: rem, core: core, awake: total(.awake),
            hasStages: hasStages, score: score, level: Level(score: score)
        )
    }

    /// 自定义评分（不是 Apple 官方睡眠分）：
    /// - 时长 50 分：4 小时为 0，7.5 小时及以上满分
    /// - 深睡 + REM 25 分：深睡占比达 15%、REM 占比达 20% 各得满分 12.5
    /// - 效率 25 分：睡着时间占在床时间 70% 为 0，90% 及以上满分
    /// 没有分期数据（老款手表或第三方来源）时，按时长和效率两项折算成 100 分。
    static func score(asleep: TimeInterval, deep: TimeInterval, rem: TimeInterval, span: TimeInterval, hasStages: Bool) -> Int {
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

        let duration = clamp((asleep / 3600 - 4) / 3.5)
        let efficiency = span > 0 ? clamp((asleep / span - 0.70) / 0.20) : 0

        let points: Double
        if hasStages, asleep > 0 {
            let deepRatio = clamp(deep / asleep / 0.15)
            let remRatio = clamp(rem / asleep / 0.20)
            points = duration * 50 + (deepRatio + remRatio) * 12.5 + efficiency * 25
        } else {
            points = (duration * 50 + efficiency * 25) / 75 * 100
        }
        return Int(points.rounded())
    }

    private static func asleepTime(_ segments: [SleepSegment]) -> TimeInterval {
        segments.filter(\.isAsleep).reduce(0) { $0 + $1.duration }
    }
}

extension Format {
    /// 7 小时 32 分 → "7h32m"
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }
}

extension SleepSummary.Level {
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .mint
        case .fair: return .yellow
        case .poor: return .orange
        }
    }
}
