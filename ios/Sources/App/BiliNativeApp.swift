import AVFoundation
import SwiftUI

@main
struct BiliNativeApp: App {
    @State private var env = AppEnvironment()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .task { await env.startServices() }
        }
    }
}
