import Foundation
import WatchConnectivity

/// 手表端的 WatchConnectivity：接收 iPhone 推来的 OBS 状态，发送指令和心率。
@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = ObsSnapshot()
    @Published private(set) var phoneReachable = false
    @Published var lastError: String?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        guard WCSession.default.isReachable else {
            lastError = "iPhone 不可达，请打开 iPhone 上的 OBS 遥控"
            return
        }
        WCSession.default.sendMessage([MessageKey.command: data], replyHandler: nil) { error in
            let message = error.localizedDescription
            Task { @MainActor in self.lastError = message }
        }
    }

    func sendHeartRate(_ bpm: Int) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([MessageKey.heartRate: bpm], replyHandler: nil, errorHandler: nil)
    }

    func requestSnapshot() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([MessageKey.requestSnapshot: true], replyHandler: { reply in
            let data = reply[MessageKey.snapshot] as? Data
            Task { @MainActor in self.apply(data) }
        }, errorHandler: nil)
    }

    private func apply(_ data: Data?) {
        guard let data, let snapshot = ObsSnapshot.decode(data) else { return }
        self.snapshot = snapshot
        lastError = nil
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[MessageKey.snapshot] as? Data
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
            self.apply(data)
            self.requestSnapshot()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
            if reachable { self.requestSnapshot() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message[MessageKey.snapshot] as? Data
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[MessageKey.snapshot] as? Data
        Task { @MainActor in self.apply(data) }
    }
}
