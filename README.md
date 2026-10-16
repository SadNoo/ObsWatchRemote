# OBS 遥控（iPhone + Apple Watch）

在 Apple Watch 上查看 OBS 推流数据（码率、网络丢帧、拥塞、CPU、帧率），控制开播/录制/切场景，并把手表实时心率推送到 OBS 直播画面。

## 架构

```
Apple Watch ──WatchConnectivity──▶ iPhone App ──obs-websocket v5──▶ 电脑上的 OBS
  · 显示状态                        · 每 2 秒采集 GetStats / GetStreamStatus
  · 发送指令                        · 执行指令
  · 测量心率（锻炼会话）            · 心率 → 文字源 + CustomEvent
```

watchOS 不允许普通 App 直接使用 WebSocket 等底层网络，所以由 iPhone 负责连接 OBS。

## 目录

| 路径 | 说明 |
|---|---|
| `project.yml` | XcodeGen 配置，用来生成 Xcode 工程 |
| `Shared/` | iPhone 和手表共用的数据模型和格式化 |
| `iOS/` | iPhone App：obs-websocket 客户端、采集、设置界面 |
| `Watch/` | 手表 App：状态页、控制页、心率页 |
| `overlay/heart-rate.html` | OBS 浏览器源用的心率动画叠加层 |

## 编译

需要 macOS + Xcode 16 以上 + [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
xcodegen generate          # 生成 ObsWatchRemote.xcodeproj
open ObsWatchRemote.xcodeproj
```

1. 在 `project.yml` 里把 `BUNDLE_ID_PREFIX` 改成你自己的（例如 `com.yourname`），重新 `xcodegen generate`。
2. Xcode → 两个 target 的 Signing & Capabilities → 选择你的 Team。
3. 选 `ObsRemote` scheme，目标选你的 iPhone，运行。手表 App 会随 iPhone App 一起安装（也可以在 iPhone 的「Watch」App 里手动安装）。

## OBS 设置

1. OBS 28 以上 → 工具 → WebSocket 服务器设置 → 勾选「开启 WebSocket 服务器」，记下端口（默认 4455）和密码。
2. iPhone 与电脑在同一局域网，App 里填电脑 IP、端口、密码，点连接。首次会弹「本地网络」权限，选允许。
3. 心率文字（简单）：在 OBS 新建一个「文本」源，命名为 `HeartRate`（与 App 里的名称一致）。
4. 心率动画（可选）：新建「浏览器」源 → 勾选「本地文件」选择 `overlay/heart-rate.html`；如果 WebSocket 有密码，改为不勾本地文件、URL 填
   `file:///完整路径/overlay/heart-rate.html?password=你的密码`。宽 400，高 160。

## 使用

- 手表上下滑动切换三页：**状态** / **控制** / **心率**。
- 心率页点「开始推送心率」会开启一次锻炼会话（不会保存到「健身」记录），iPhone 端随即开始把心率写入 OBS。
- 指标颜色：绿色正常，黄色注意，红色异常。
  - 网络：丢帧率 > 0.1% 或拥塞 > 15% 为黄，丢帧率 ≥ 1%、拥塞 ≥ 50% 或正在重连为红。
  - CPU（OBS 进程）：≥ 60% 黄，≥ 85% 红。

## 已知限制

- iOS 会在 App 退到后台后很快断开网络。直播时让 iPhone App 停留在前台（默认开启屏幕常亮），建议接电源。
- 码率是用两次采样的已发送字节数差值算出来的，每 2 秒刷新一次。
- 密码存放在 UserDefaults，仅适合个人使用。
