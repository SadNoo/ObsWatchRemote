import HealthKit

/// 从「健康」读取昨晚的睡眠记录（Apple Watch 记录的数据会同步到 iPhone）。
final class SleepAnalyzer {
    enum SleepError: LocalizedError {
        case unavailable

        var errorDescription: String? { "此设备不支持健康数据" }
    }

    private let store = HKHealthStore()

    /// 统计范围：昨天 18:00 到现在。没有数据（或未授权）时返回 nil。
    func lastNight(now: Date = Date()) async throws -> SleepSummary? {
        guard HKHealthStore.isHealthDataAvailable() else { throw SleepError.unavailable }

        let type = HKCategoryType(.sleepAnalysis)
        try await store.requestAuthorization(toShare: [], read: [type])

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .hour, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)

        let segments = samples.compactMap { sample -> SleepSegment? in
            guard let stage = Self.stage(for: sample.value) else { return nil }
            return SleepSegment(
                stage: stage,
                start: max(sample.startDate, start),
                end: min(sample.endDate, now),
                source: sample.sourceRevision.source.bundleIdentifier
            )
        }
        return SleepSummary.make(from: segments)
    }

    private static func stage(for value: Int) -> SleepSegment.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .asleepUnspecified: return .unspecified
        default: return nil
        }
    }
}
