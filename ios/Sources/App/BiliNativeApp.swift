import AVFoundation
import SwiftUI
import DevLog

@main
struct BiliNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()

    init() {
        DevLogSetup.install()
        BorrowedIcon.registerFont()
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
                .task { DevLogSetup.apply(env.settings) }
        }
    }
}
