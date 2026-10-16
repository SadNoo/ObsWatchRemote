import SwiftUI

struct StatusPage: View {
    @EnvironmentObject private var session: WatchSessionManager

    private var s: ObsSnapshot { session.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                header

                if !session.phoneReachable {
                    notice("iPhone 不可达，请打开 iPhone 上的 OBS 遥控")
                } else if let error = s.errorMessage {
                    notice(error)
                }

                if s.connection == .connected {
                    if s.isStreaming {
                        metric("码率", Format.bitrate(s.bitrateKbps), s.networkLevel)
                        metric("丢帧", "\(s.droppedFrames) · \(Format.percent(s.droppedPercent, digits: 2))", s.networkLevel)
                        metric("拥塞", Format.percent(s.congestion * 100, digits: 0), s.networkLevel)
                    }
                    metric("CPU", Format.percent(s.cpuUsage), s.cpuLevel)
                    metric("FPS", String(format: "%.1f", s.activeFps), s.renderLevel)
                    metric("渲染跳帧", Format.percent(s.renderSkippedPercent, digits: 2), s.renderLevel)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("状态")
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Circle().fill(s.statusColor).frame(width: 8, height: 8)
                Text(s.statusText).font(.headline)
                Spacer()
                if s.isStreaming {
                    // 两次同步之间本地补上流逝的秒数，让时长每秒跳动
                    Text(Format.duration(s.streamDuration + max(0, context.date.timeIntervalSince(s.updatedAt))))
                        .font(.caption)
                        .monospacedDigit()
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ level: HealthLevel) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(level == .good ? Color.primary : level.color)
        }
        .font(.system(.body, design: .rounded))
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.orange)
    }
}
