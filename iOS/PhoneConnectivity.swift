import Foundation
import WatchConnectivity

/// iPhone 端的 WatchConnectivity：把状态推给手表，接收手表的指令和心率。
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    var onCommand: (@MainActor (WatchCommand) -> Void)?
    var onHeartRate: (@MainActor (Int) -> Void)?
    var snapshotProvider: (@MainActor () -> ObsSnapshot)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: ObsSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = snapshot.encoded()
        else { return }

        let payload: [String: Any] = [MessageKey.snapshot: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            // 手表 App 不在前台时，下次打开会拿到最新一份
            try? session.updateApplicationContext(payload)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // 用户切换了配对的手表
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        Task { @MainActor in
            let data = self.snapshotProvider?().encoded()
            replyHandler(data.map { [MessageKey.snapshot: $0] } ?? [:])
        }
    }

    private func handle(_ message: [String: Any]) {
        if let data = message[MessageKey.command] as? Data,
           let command = try? JSONDecoder().decode(WatchCommand.self, from: data)
        {
            Task { @MainActor in self.onCommand?(command) }
        }
        if let bpm = message[MessageKey.heartRate] as? Int {
            Task { @MainActor in self.onHeartRate?(bpm) }
        }
    }
}
