import SwiftUI

struct HeartRatePage: View {
    @EnvironmentObject private var session: WatchSessionManager
    @EnvironmentObject private var heart: HeartRateManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: heart.isRunning)
                Text(heart.bpm.map(String.init) ?? "--")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("BPM").font(.caption).foregroundStyle(.secondary)
            }

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(heart.isRunning ? "停止推送" : "开始推送心率") {
                Task {
                    if heart.isRunning {
                        await heart.stop()
                        session.send(.setHeartRateForwarding(false))
                    } else {
                        await heart.start()
                        if heart.isRunning { session.send(.setHeartRateForwarding(true)) }
                    }
                }
            }
            .tint(heart.isRunning ? .red : .pink)

            if let error = heart.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
        .navigationTitle("心率")
    }

    private var statusText: String {
        guard heart.isRunning else { return "开始后会持续测量心率并发送到 OBS" }
        if !session.phoneReachable { return "iPhone 不可达，暂未推送" }
        return session.snapshot.heartRateForwarding ? "正在推送到 OBS" : "测量中（iPhone 未开启推送）"
    }
}
