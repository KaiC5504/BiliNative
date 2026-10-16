import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView()
            .onChange(of: scenePhase) {
                if scenePhase == .active, env.account == .unknown {
                    Task { await env.refreshAccount() }
                }
            }
    }
}
