import SwiftUI

@main
struct ObsRemoteApp: App {
    @StateObject private var obs = OBSController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(obs)
        }
    }
}
