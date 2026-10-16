import SwiftUI

@main
struct ObsRemoteWatchApp: App {
    @StateObject private var session = WatchSessionManager()
    @StateObject private var heart = HeartRateManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(heart)
                .onAppear {
                    heart.onHeartRate = { [weak session] bpm in session?.sendHeartRate(bpm) }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { StatusPage() }
            NavigationStack { ControlPage() }
            NavigationStack { HeartRatePage() }
        }
        .tabViewStyle(.verticalPage)
    }
}
