import Foundation

struct ConnectionSettings: Codable, Equatable {
    var host = "192.168.1.100"
    var port = 4455
    var password = ""
    var autoConnect = true
    var keepScreenAwake = true

    /// OBS 中用于显示心率的文字源名称，留空则只广播 CustomEvent（给网页叠加层用）。
    var heartRateSourceName = "HeartRate"
    /// {bpm} 会被替换为心率数值。
    var heartRateFormat = "❤️ {bpm}"

    var url: URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, (1...65535).contains(port) else { return nil }
        return URL(string: "ws://\(trimmed):\(port)")
    }

    func heartRateText(_ bpm: Int) -> String {
        heartRateFormat.replacingOccurrences(of: "{bpm}", with: String(bpm))
    }

    // 个人自用，简单存 UserDefaults；如需更安全可把 password 移到 Keychain。
    private static let key = "connectionSettings"

    static func load() -> ConnectionSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data)
        else { return ConnectionSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
