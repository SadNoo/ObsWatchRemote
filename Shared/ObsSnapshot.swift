import Foundation

/// iPhone 与手表之间同步的 OBS 状态。由 iPhone 采集，手表只负责展示。
struct ObsSnapshot: Codable, Equatable {
    enum Connection: String, Codable {
        case disconnected, connecting, connected, failed
    }

    var connection: Connection = .disconnected
    var errorMessage: String?

    // 输出状态
    var isStreaming = false
    var isReconnecting = false
    var isRecording = false
    var streamDuration: Double = 0  // 秒

    // 推流网络
    var bitrateKbps: Double = 0
    var congestion: Double = 0  // 0...1
    var droppedFrames = 0  // 网络丢帧（GetStreamStatus.outputSkippedFrames）
    var totalFrames = 0

    // 性能
    var cpuUsage: Double = 0  // OBS 进程 CPU 百分比
    var memoryUsageMB: Double = 0
    var activeFps: Double = 0
    var renderSkippedFrames = 0
    var renderTotalFrames = 0

    // 场景
    var scenes: [String] = []
    var currentScene = ""

    // 心率
    var heartRateForwarding = false

    // 昨晚睡眠（iPhone 从「健康」读取）
    var sleep: SleepSummary?

    var updatedAt = Date()

    var droppedPercent: Double {
        totalFrames > 0 ? Double(droppedFrames) / Double(totalFrames) * 100 : 0
    }

    var renderSkippedPercent: Double {
        renderTotalFrames > 0 ? Double(renderSkippedFrames) / Double(renderTotalFrames) * 100 : 0
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> ObsSnapshot? {
        try? JSONDecoder().decode(ObsSnapshot.self, from: data)
    }
}

/// 手表发给 iPhone 的控制指令。
enum WatchCommand: Codable, Equatable {
    case toggleStream
    case toggleRecord
    case setScene(String)
    case setHeartRateForwarding(Bool)
    /// 重新读取睡眠并推送到 OBS
    case showSleep
}

/// WatchConnectivity 消息字典中使用的键。
enum MessageKey {
    static let snapshot = "snapshot"
    static let command = "command"
    static let heartRate = "heartRate"
    static let requestSnapshot = "requestSnapshot"
}
