import SwiftUI

enum HealthLevel {
    case good, warning, bad

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .bad: return .red
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        if t >= 3600 {
            return String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60)
        }
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    static func bitrate(_ kbps: Double) -> String {
        kbps >= 1000 ? String(format: "%.2f Mbps", kbps / 1000) : String(format: "%.0f kbps", kbps)
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value)
    }
}

extension ObsSnapshot {
    /// 网络丢帧、拥塞、重连综合判断。
    var networkLevel: HealthLevel {
        if isReconnecting || droppedPercent >= 1 || congestion >= 0.5 { return .bad }
        if droppedPercent > 0.1 || congestion > 0.15 { return .warning }
        return .good
    }

    var cpuLevel: HealthLevel {
        if cpuUsage >= 85 { return .bad }
        if cpuUsage >= 60 { return .warning }
        return .good
    }

    var renderLevel: HealthLevel {
        if renderSkippedPercent >= 1 { return .bad }
        if renderSkippedPercent > 0.1 { return .warning }
        return .good
    }

    var statusText: String {
        switch connection {
        case .disconnected: return "未连接 OBS"
        case .connecting: return "正在连接…"
        case .failed: return "连接失败"
        case .connected:
            if isReconnecting { return "推流重连中" }
            return isStreaming ? "直播中" : "未推流"
        }
    }

    var statusColor: Color {
        switch connection {
        case .connected:
            if isReconnecting { return .orange }
            return isStreaming ? .red : .gray
        case .connecting: return .yellow
        case .failed: return .orange
        case .disconnected: return .gray
        }
    }
}
