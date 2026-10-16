import Foundation
import HealthKit

/// 通过一次 HKWorkoutSession 获取实时心率（约每 1–5 秒一次），并保持 App 在后台运行。
@MainActor
final class HeartRateManager: NSObject, ObservableObject {
    @Published private(set) var bpm: Int?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    var onHeartRate: ((Int) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() async {
        guard !isRunning else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "此设备不支持健康数据"
            return
        }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [HKQuantityType(.heartRate)])

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .indoor

            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = "无法开始测量：\(error.localizedDescription)"
            session?.end()
            session = nil
            builder = nil
        }
    }

    func stop() async {
        guard let session, let builder else { return }
        // 先清状态，避免 session.end() 触发的代理回调再次进入 stop()
        self.session = nil
        self.builder = nil
        isRunning = false
        bpm = nil

        session.end()
        try? await builder.endCollection(at: Date())
        // 不保存到「健身」记录，避免每场直播都多一条锻炼
        builder.discardWorkout()
    }

    private func handleSessionEnded() {
        session = nil
        builder = nil
        isRunning = false
    }
}

extension HeartRateManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended || toState == .stopped {
            Task { @MainActor in
                // 被系统或用户在别处结束时同步状态
                if self.session === workoutSession {
                    await self.stop()
                }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.errorMessage = "测量中断：\(message)"
            self.handleSessionEnded()
        }
    }
}

extension HeartRateManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let quantity = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()
        else { return }
        let value = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in
            self.bpm = value
            self.onHeartRate?(value)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
