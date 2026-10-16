import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var obs: OBSController
    @State private var confirmStopStream = false

    private var s: ObsSnapshot { obs.snapshot }
    private var isConnected: Bool { s.connection == .connected }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                if isConnected {
                    statsSection
                    controlSection
                }
                heartRateSection
                optionsSection
            }
            .navigationTitle("OBS 遥控")
            .confirmationDialog("确定停止直播？", isPresented: $confirmStopStream, titleVisibility: .visible) {
                Button("停止直播", role: .destructive) { obs.perform(.toggleStream) }
            }
        }
    }

    // MARK: - 连接

    private var connectionSection: some View {
        Section {
            HStack {
                Circle().fill(s.statusColor).frame(width: 10, height: 10)
                Text(s.statusText)
                Spacer()
                if s.connection == .connecting { ProgressView() }
            }
            if let error = s.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            TextField("电脑 IP", text: $obs.settings.host)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("端口", value: $obs.settings.port, format: .number.grouping(.never))
                .keyboardType(.numberPad)
            SecureField("密码（OBS → 工具 → WebSocket 服务器设置）", text: $obs.settings.password)

            if s.connection == .disconnected || s.connection == .failed {
                Button("连接") { obs.connect() }
            } else {
                Button("断开", role: .destructive) { obs.disconnect() }
            }
        } header: {
            Text("连接")
        }
    }

    // MARK: - 统计

    private var statsSection: some View {
        Section("推流状态") {
            if s.isStreaming {
                row("直播时长", Format.duration(s.streamDuration))
                row("码率", Format.bitrate(s.bitrateKbps), s.networkLevel)
                row("网络丢帧", "\(s.droppedFrames)（\(Format.percent(s.droppedPercent, digits: 2))）", s.networkLevel)
                row("网络拥塞", Format.percent(s.congestion * 100, digits: 0), s.networkLevel)
            }
            row("OBS CPU", Format.percent(s.cpuUsage), s.cpuLevel)
            row("内存", String(format: "%.0f MB", s.memoryUsageMB))
            row("帧率", String(format: "%.1f fps", s.activeFps))
            row("渲染跳帧", "\(s.renderSkippedFrames)（\(Format.percent(s.renderSkippedPercent, digits: 2))）", s.renderLevel)
        }
    }

    private func row(_ title: String, _ value: String, _ level: HealthLevel? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(level.map { $0 == .good ? Color.primary : $0.color } ?? .primary)
        }
    }

    // MARK: - 控制

    private var controlSection: some View {
        Section("控制") {
            Button(s.isStreaming ? "停止直播" : "开始直播", role: s.isStreaming ? .destructive : nil) {
                if s.isStreaming { confirmStopStream = true } else { obs.perform(.toggleStream) }
            }
            Button(s.isRecording ? "停止录制" : "开始录制") { obs.perform(.toggleRecord) }

            if !s.scenes.isEmpty {
                Picker("场景", selection: Binding(
                    get: { s.currentScene },
                    set: { obs.perform(.setScene($0)) }
                )) {
                    ForEach(s.scenes, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    // MARK: - 心率

    private var heartRateSection: some View {
        Section {
            Toggle("推送心率到 OBS", isOn: Binding(
                get: { s.heartRateForwarding },
                set: { obs.perform(.setHeartRateForwarding($0)) }
            ))
            HStack {
                Text("最新心率")
                Spacer()
                Text(obs.lastHeartRate.map { "\($0) BPM" } ?? "—").monospacedDigit()
            }
            TextField("OBS 文字源名称", text: $obs.settings.heartRateSourceName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("显示格式", text: $obs.settings.heartRateFormat)
        } header: {
            Text("心率")
        } footer: {
            Text("在手表的「心率」页点开始即可。会更新 OBS 中同名文字源的内容（{bpm} 替换为数值），同时广播 CustomEvent 给网页叠加层。文字源名称留空则只广播事件。")
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("启动时自动连接", isOn: $obs.settings.autoConnect)
            Toggle("保持屏幕常亮", isOn: $obs.settings.keepScreenAwake)
        } footer: {
            Text("iOS 会在 App 进入后台后很快断开网络连接。直播时请让本 App 停留在前台（建议开启屏幕常亮并接上电源），手表才能持续拿到数据。")
        }
    }
}
