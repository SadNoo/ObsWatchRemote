import Foundation
import UIKit

/// 连接 OBS、定时采集统计、执行指令、转发心率，并把状态同步给手表。
@MainActor
final class OBSController: ObservableObject {
    @Published private(set) var snapshot = ObsSnapshot() {
        didSet { connectivity.send(snapshot) }
    }

    @Published private(set) var lastHeartRate: Int?

    @Published var settings: ConnectionSettings {
        didSet {
            settings.save()
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
        }
    }

    private let client = OBSWebSocketClient()
    private let connectivity = PhoneConnectivity()
    private let sleepAnalyzer = SleepAnalyzer()
    private var lastSleepPush: Date?
    private var pollTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var wantsConnection = false
    private var lastOutputBytes: (bytes: Double, time: Date)?

    private static let pollInterval: Duration = .seconds(2)
    private static let reconnectDelay: Duration = .seconds(3)
    /// CustomEvent 不会保留，定期重发，让之后才加载的网页叠加层也能拿到
    private static let sleepRebroadcastInterval: TimeInterval = 60

    init() {
        settings = ConnectionSettings.load()
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake

        client.onEvent = { [weak self] type, data in self?.handleEvent(type, data) }
        client.onDisconnect = { [weak self] error in self?.handleDisconnect(error) }

        connectivity.onCommand = { [weak self] command in self?.perform(command) }
        connectivity.onHeartRate = { [weak self] bpm in self?.receiveHeartRate(bpm) }
        connectivity.snapshotProvider = { [weak self] in self?.snapshot ?? ObsSnapshot() }
        connectivity.activate()

        if settings.autoConnect { connect() }
        Task { await refreshSleep(push: false) }
    }

    // MARK: - 连接

    func connect() {
        wantsConnection = true
        reconnectTask?.cancel()
        Task { await establish() }
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        pollTask?.cancel()
        client.disconnect()
        snapshot = ObsSnapshot(heartRateForwarding: snapshot.heartRateForwarding, sleep: snapshot.sleep)
    }

    private func establish() async {
        guard let url = settings.url else {
            snapshot.connection = .failed
            snapshot.errorMessage = "地址或端口无效"
            return
        }
        snapshot.connection = .connecting
        do {
            try await client.connect(url: url, password: settings.password)
            snapshot.connection = .connected
            snapshot.errorMessage = nil
            await refreshScenes()
            startPolling()
            await pushSleep()
        } catch {
            snapshot.connection = .failed
            snapshot.errorMessage = error.localizedDescription
            // 密码错误时重试没有意义
            if case OBSError.authFailed = error { return }
            scheduleReconnect()
        }
    }

    private func handleDisconnect(_ error: Error) {
        pollTask?.cancel()
        lastOutputBytes = nil
        snapshot = ObsSnapshot(
            connection: .failed,
            errorMessage: "连接断开：\(error.localizedDescription)",
            heartRateForwarding: snapshot.heartRateForwarding,
            sleep: snapshot.sleep
        )
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard wantsConnection else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reconnectDelay)
            guard !Task.isCancelled, let self, self.wantsConnection else { return }
            await self.establish()
        }
    }

    // MARK: - 采集

    private func startPolling() {
        pollTask?.cancel()
        lastOutputBytes = nil
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func poll() async {
        do {
            let stats = try await client.request("GetStats")
            let stream = try await client.request("GetStreamStatus")
            let record = try await client.request("GetRecordStatus")

            var s = snapshot
            s.cpuUsage = obsDouble(stats["cpuUsage"])
            s.memoryUsageMB = obsDouble(stats["memoryUsage"])
            s.activeFps = obsDouble(stats["activeFps"])
            s.renderSkippedFrames = obsInt(stats["renderSkippedFrames"])
            s.renderTotalFrames = obsInt(stats["renderTotalFrames"])

            s.isStreaming = stream["outputActive"] as? Bool ?? false
            s.isReconnecting = stream["outputReconnecting"] as? Bool ?? false
            s.streamDuration = obsDouble(stream["outputDuration"]) / 1000
            s.congestion = obsDouble(stream["outputCongestion"])
            s.droppedFrames = obsInt(stream["outputSkippedFrames"])
            s.totalFrames = obsInt(stream["outputTotalFrames"])

            // obs-websocket 不直接给码率，用两次 outputBytes 的差值计算
            let bytes = obsDouble(stream["outputBytes"])
            let now = Date()
            if s.isStreaming, let last = lastOutputBytes, bytes >= last.bytes {
                let elapsed = now.timeIntervalSince(last.time)
                if elapsed > 0 { s.bitrateKbps = (bytes - last.bytes) * 8 / 1000 / elapsed }
            } else if !s.isStreaming {
                s.bitrateKbps = 0
            }
            lastOutputBytes = s.isStreaming ? (bytes, now) : nil

            s.isRecording = record["outputActive"] as? Bool ?? false
            s.updatedAt = now
            snapshot = s

            if lastSleepPush.map({ now.timeIntervalSince($0) >= Self.sleepRebroadcastInterval }) ?? true {
                await pushSleep(announce: false)
            }
        } catch OBSError.notConnected {
            // 断线由 handleDisconnect 处理
        } catch {
            snapshot.errorMessage = error.localizedDescription
        }
    }

    private func refreshScenes() async {
        do {
            let list = try await client.request("GetSceneList")
            // OBS 返回的 sceneIndex 越大越靠上，按界面顺序排列
            let scenes = (list["scenes"] as? [OBSJSON] ?? [])
                .sorted { obsInt($0["sceneIndex"]) > obsInt($1["sceneIndex"]) }
                .compactMap { $0["sceneName"] as? String }
            snapshot.scenes = scenes
            snapshot.currentScene = list["currentProgramSceneName"] as? String ?? ""
        } catch {
            snapshot.errorMessage = error.localizedDescription
        }
    }

    private func handleEvent(_ type: String, _ data: OBSJSON) {
        switch type {
        case "CurrentProgramSceneChanged":
            if let name = data["sceneName"] as? String { snapshot.currentScene = name }
        case "SceneListChanged", "SceneNameChanged", "SceneCreated", "SceneRemoved":
            Task { await refreshScenes() }
        case "StreamStateChanged":
            let active = data["outputActive"] as? Bool ?? false
            snapshot.isStreaming = active
            if !active {
                snapshot.bitrateKbps = 0
                lastOutputBytes = nil
            }
        case "RecordStateChanged":
            snapshot.isRecording = data["outputActive"] as? Bool ?? false
        default:
            break
        }
    }

    // MARK: - 指令

    func perform(_ command: WatchCommand) {
        switch command {
        case let .setHeartRateForwarding(on):
            snapshot.heartRateForwarding = on
            return
        case .showSleep:
            Task { await refreshSleep(push: true) }
            return
        default:
            break
        }
        Task {
            do {
                switch command {
                case .toggleStream: try await client.request("ToggleStream")
                case .toggleRecord: try await client.request("ToggleRecord")
                case let .setScene(name): try await client.request("SetCurrentProgramScene", ["sceneName": name])
                case .setHeartRateForwarding, .showSleep: break
                }
                await poll()
            } catch {
                snapshot.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 心率

    func receiveHeartRate(_ bpm: Int) {
        lastHeartRate = bpm
        guard snapshot.heartRateForwarding, client.isIdentified else { return }
        let sourceName = settings.heartRateSourceName.trimmingCharacters(in: .whitespaces)
        let text = settings.heartRateText(bpm)
        Task {
            // 两条路径互不影响：文字源写失败时，网页叠加层照样能收到心率
            var failures: [String] = []
            if !sourceName.isEmpty {
                do {
                    try await client.request("SetInputSettings", [
                        "inputName": sourceName,
                        "inputSettings": ["text": text],
                        "overlay": true,
                    ])
                } catch {
                    failures.append("文字源「\(sourceName)」：\(error.localizedDescription)")
                }
            }
            // 给网页叠加层（overlay/heart-rate.html）用
            do {
                try await client.request("BroadcastCustomEvent", [
                    "eventData": ["type": "heartRate", "bpm": bpm],
                ])
            } catch {
                failures.append("叠加层事件：\(error.localizedDescription)")
            }
            if !failures.isEmpty {
                snapshot.errorMessage = "心率推送失败：" + failures.joined(separator: "；")
            }
        }
    }

    // MARK: - 睡眠

    /// 重新读取昨晚睡眠；push 为 true 时立即推送到 OBS。
    func refreshSleep(push: Bool) async {
        do {
            snapshot.sleep = try await sleepAnalyzer.lastNight()
            if snapshot.sleep == nil, push {
                snapshot.errorMessage = "没有找到昨晚的睡眠记录（需要佩戴手表睡觉，并允许读取睡眠数据）"
            }
        } catch {
            snapshot.errorMessage = "读取睡眠失败：\(error.localizedDescription)"
        }
        if push { await pushSleep() }
    }

    /// announce 为 true 表示主动展示（连接时、手动推送），叠加层会重新弹出；定期重发为 false。
    private func pushSleep(announce: Bool = true) async {
        guard settings.sleepEnabled, let sleep = snapshot.sleep, client.isIdentified else { return }
        lastSleepPush = Date()
        do {
            let sourceName = settings.sleepSourceName.trimmingCharacters(in: .whitespaces)
            if !sourceName.isEmpty {
                try await client.request("SetInputSettings", [
                    "inputName": sourceName,
                    "inputSettings": ["text": settings.sleepText(sleep)],
                    "overlay": true,
                ])
            }
            // 给网页叠加层（overlay/sleep-status.html）用
            try await client.request("BroadcastCustomEvent", [
                "eventData": [
                    "type": "sleep",
                    "score": sleep.score,
                    "level": sleep.level.rawValue,
                    "label": sleep.level.label,
                    "emoji": sleep.level.emoji,
                    "asleepMinutes": Int(sleep.asleep / 60),
                    "deepMinutes": Int(sleep.deep / 60),
                    "remMinutes": Int(sleep.rem / 60),
                    "efficiency": Int(sleep.efficiency * 100),
                    "hasStages": sleep.hasStages,
                    "announce": announce,
                ],
            ])
        } catch {
            snapshot.errorMessage = "睡眠状态推送失败：\(error.localizedDescription)"
        }
    }
}
