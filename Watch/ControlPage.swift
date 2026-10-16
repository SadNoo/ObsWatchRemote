import SwiftUI

struct ControlPage: View {
    @EnvironmentObject private var session: WatchSessionManager
    @State private var confirmStopStream = false

    private var s: ObsSnapshot { session.snapshot }

    var body: some View {
        List {
            Section {
                Button {
                    if s.isStreaming { confirmStopStream = true } else { session.send(.toggleStream) }
                } label: {
                    Label(s.isStreaming ? "停止直播" : "开始直播",
                          systemImage: s.isStreaming ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                }
                .tint(s.isStreaming ? .red : .green)

                Button {
                    session.send(.toggleRecord)
                } label: {
                    Label(s.isRecording ? "停止录制" : "开始录制",
                          systemImage: s.isRecording ? "stop.fill" : "record.circle")
                }
            }

            if !s.scenes.isEmpty {
                Section("场景") {
                    ForEach(s.scenes, id: \.self) { scene in
                        Button {
                            session.send(.setScene(scene))
                        } label: {
                            HStack {
                                Text(scene).lineLimit(1)
                                Spacer()
                                if scene == s.currentScene {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }

            if let error = session.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
        .disabled(s.connection != .connected || !session.phoneReachable)
        .navigationTitle("控制")
        .confirmationDialog("确定停止直播？", isPresented: $confirmStopStream) {
            Button("停止直播", role: .destructive) { session.send(.toggleStream) }
        }
    }
}
