import AVFoundation
import SwiftUI
import DevLog

@main
struct BiliNativeApp: App {
    @State private var env = AppEnvironment()

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            Logger.shared.error(.app, "audio session category failed", ["error": .init(String(describing: error))])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .task { await env.startServices() }
        }
    }
}
