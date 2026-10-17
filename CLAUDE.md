# ObsWatchRemote

iOS + watchOS SwiftUI app that monitors/controls OBS via obs-websocket v5 and forwards Apple Watch heart rate to OBS. See README.md (Chinese) for the architecture.

CI (`.github/workflows/build.yml`) builds both targets for the simulators on every push to main (Xcode 26.6 at the time of writing; 0 warnings) and checks the watch app is embedded at `ObsRemote.app/Watch/`. Nothing has been run on a real device yet.

## Build

The Xcode project is generated — edit `project.yml`, never the `.xcodeproj`.

```bash
xcodegen generate
xcodebuild -project ObsWatchRemote.xcodeproj -scheme ObsRemote \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ObsWatchRemote.xcodeproj -scheme ObsRemoteWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Pipe through `| xcbeautify` or `| grep -E "error|warning: .*\.swift"` to keep output short.

## Things to check when fixing the build

- The watch app is a single-target watchOS app (`type: application`, `platform: watchOS`, `WKApplication: true`) embedded in the iOS app via the `dependencies` entry. If XcodeGen embeds it in the wrong place, fix it in `project.yml` (it must land in `ObsRemote.app/Watch/`).
- `SWIFT_VERSION` is 5.0 on purpose; concurrency warnings are acceptable, errors are not.
- Do not add third-party dependencies.

## Conventions

- UI strings and code comments are in Simplified Chinese.
- Keep the obs-websocket protocol code in `iOS/OBSWebSocketClient.swift`; the watch never talks to OBS directly (watchOS blocks low-level networking).
