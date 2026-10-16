import SwiftUI

@main
struct BiliNativeApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
        }
    }
}
