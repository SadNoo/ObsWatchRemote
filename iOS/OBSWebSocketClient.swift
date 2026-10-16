import CryptoKit
import Foundation

typealias OBSJSON = [String: Any]

enum OBSError: LocalizedError {
    case notConnected
    case authFailed
    case timeout
    case requestFailed(type: String, code: Int, comment: String?)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接到 OBS"
        case .authFailed: return "密码错误（OBS 拒绝认证）"
        case .timeout: return "连接超时，请检查 IP、端口和防火墙"
        case let .requestFailed(type, code, comment):
            return "\(type) 失败（\(code)）\(comment.map { "：\($0)" } ?? "")"
        }
    }
}

/// obs-websocket v5 协议客户端（OBS 28+ 内置）。
/// 协议文档：https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md
@MainActor
final class OBSWebSocketClient {
    private enum OpCode: Int {
        case hello = 0, identify = 1, identified = 2, event = 5, request = 6, requestResponse = 7
    }

    /// General(1) | Scenes(4) | Outputs(64)
    private static let eventSubscriptions = 1 | 4 | 64

    var onEvent: ((String, OBSJSON) -> Void)?
    /// 已建立的连接意外断开时调用（主动 disconnect 不会调用）。
    var onDisconnect: ((Error) -> Void)?

    private(set) var isIdentified = false

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var password = ""
    private var identifyContinuation: CheckedContinuation<Void, Error>?
    private var pending: [String: CheckedContinuation<OBSJSON, Error>] = [:]

    func connect(url: URL, password: String, timeout: Duration = .seconds(8)) async throws {
        teardown(error: OBSError.notConnected, notify: false)
        self.password = password

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        Task { [weak self] in await self?.receiveLoop(task) }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, self.task === task, !self.isIdentified else { return }
            self.teardown(error: OBSError.timeout, notify: false)
        }

        try await withCheckedThrowingContinuation { continuation in
            identifyContinuation = continuation
        }
    }

    func disconnect() {
        teardown(error: OBSError.notConnected, notify: false)
    }

    @discardableResult
    func request(_ type: String, _ data: OBSJSON? = nil) async throws -> OBSJSON {
        guard let task, isIdentified else { throw OBSError.notConnected }
        let id = UUID().uuidString
        var d: OBSJSON = ["requestType": type, "requestId": id]
        if let data { d["requestData"] = data }
        let text = try Self.encode(op: .request, d: d)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await task.send(.string(text))
                } catch {
                    self.pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 接收

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                guard self.task === task else { return }
                let closedForAuth = task.closeCode.rawValue == 4009
                teardown(error: closedForAuth ? OBSError.authFailed : error, notify: isIdentified)
                return
            }
            guard self.task === task else { return }

            let data: Data
            switch message {
            case let .string(text): data = Data(text.utf8)
            case let .data(raw): data = raw
            @unknown default: continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? OBSJSON,
                  let rawOp = object["op"] as? Int, let op = OpCode(rawValue: rawOp),
                  let d = object["d"] as? OBSJSON
            else { continue }
            handle(op: op, d: d, task: task)
        }
    }

    private func handle(op: OpCode, d: OBSJSON, task: URLSessionWebSocketTask) {
        switch op {
        case .hello:
            var identify: OBSJSON = ["rpcVersion": 1, "eventSubscriptions": Self.eventSubscriptions]
            if let auth = d["authentication"] as? OBSJSON,
               let challenge = auth["challenge"] as? String,
               let salt = auth["salt"] as? String
            {
                identify["authentication"] = Self.authString(password: password, salt: salt, challenge: challenge)
            }
            guard let text = try? Self.encode(op: .identify, d: identify) else { return }
            Task { try? await task.send(.string(text)) }

        case .identified:
            isIdentified = true
            identifyContinuation?.resume()
            identifyContinuation = nil

        case .event:
            guard let type = d["eventType"] as? String else { return }
            onEvent?(type, d["eventData"] as? OBSJSON ?? [:])

        case .requestResponse:
            guard let id = d["requestId"] as? String,
                  let continuation = pending.removeValue(forKey: id)
            else { return }
            let status = d["requestStatus"] as? OBSJSON ?? [:]
            if status["result"] as? Bool == true {
                continuation.resume(returning: d["responseData"] as? OBSJSON ?? [:])
            } else {
                continuation.resume(throwing: OBSError.requestFailed(
                    type: d["requestType"] as? String ?? "请求",
                    code: status["code"] as? Int ?? 0,
                    comment: status["comment"] as? String
                ))
            }

        case .identify, .request:
            break
        }
    }

    private func teardown(error: Error, notify: Bool) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isIdentified = false

        identifyContinuation?.resume(throwing: error)
        identifyContinuation = nil

        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(throwing: error) }

        if notify { onDisconnect?(error) }
    }

    // MARK: - 工具

    private static func encode(op: OpCode, d: OBSJSON) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["op": op.rawValue, "d": d])
        return String(decoding: data, as: UTF8.self)
    }

    /// base64(sha256(base64(sha256(password + salt)) + challenge))
    static func authString(password: String, salt: String, challenge: String) -> String {
        let secret = Data(SHA256.hash(data: Data((password + salt).utf8))).base64EncodedString()
        return Data(SHA256.hash(data: Data((secret + challenge).utf8))).base64EncodedString()
    }
}

/// JSONSerialization 返回 NSNumber，统一转换。
func obsDouble(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }
func obsInt(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
