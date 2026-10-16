import SwiftUI

/// The account avatar at the left of the home's top row; a grey head until the account has a face.
struct AccountAvatar: View {
    let face: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Theme.pageGrey
            if let face, !face.isEmpty {
                RemoteImage(face)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Theme.divider)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// What the avatar opens: the account (name, 大会员, 退出 or 登录), then 历史记录, 最近打开 and 设置.
/// The official app keeps these on 我的 (02); with no tab bar they drop down from the avatar instead.
struct AvatarMenu: View {
    enum Item {
        case login, history, recents, settings
    }

    @Environment(AppEnvironment.self) private var env
    let onSelect: (Item) -> Void

    var body: some View {
        VStack(spacing: 0) {
            account
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Theme.divider.frame(height: 0.5)
            row("历史记录", systemImage: "clock.arrow.circlepath", item: .history)
            row("最近打开", systemImage: "play.square.stack", item: .recents)
            row("设置", systemImage: "gearshape", item: .settings)
        }
        .padding(.bottom, 4)
        .frame(width: 248)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.scrim, radius: 16, y: 6)
    }

    @ViewBuilder
    private var account: some View {
        HStack(spacing: 10) {
            AccountAvatar(face: env.face, size: 40)
            switch env.account {
            case .unknown:
                if env.accountCheckFailed {
                    Button("无法获取账号信息，点按重试") { Task { await env.refreshAccount() } }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.reason)
                } else {
                    ProgressView()
                }
                Spacer(minLength: 0)
            case .loggedOut:
                Text("未登录")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                pill("登录") { onSelect(.login) }
            case .expired:
                Text("登录已过期")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                pill("重新登录") { onSelect(.login) }
            case .loggedIn(let name, let vip):
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(vip ? Theme.pink : Theme.text)
                        .lineLimit(1)
                    if vip {
                        Text("大会员")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.card)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Theme.pink, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                Button("退出") { Task { await env.logout() } }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(minHeight: 40)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.card)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Theme.pink, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, systemImage: String, item: Item) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
