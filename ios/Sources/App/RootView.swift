import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            List {
                Section("账号") { AccountRow(showLogin: $showLogin) }
                Section { Text("版本 \(AppInfo.version)") }
            }
            .navigationTitle(AppInfo.displayName)
            .sheet(isPresented: $showLogin) { LoginView() }
            .task { await env.refreshAccount() }
        }
    }
}

struct AccountRow: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var showLogin: Bool

    var body: some View {
        switch env.account {
        case .unknown:
            ProgressView()
        case .loggedOut:
            Button("登录哔哩哔哩") { showLogin = true }
        case .expired:
            Button("登录已过期，重新登录") { showLogin = true }
                .foregroundStyle(.orange)
        case .loggedIn(let name, let vip):
            HStack {
                Text(name)
                if vip {
                    Text("大会员")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.pink.opacity(0.15), in: Capsule())
                        .foregroundStyle(.pink)
                }
                Spacer()
                Button("退出") { Task { await env.logout() } }
                    .font(.footnote)
            }
        }
    }
}
