import SwiftUI
import AppLogic
import BiliAPI

/// The uploader with 粉丝 and 视频 counts and the 关注 pill (03). A video made by several people shows their avatars
/// instead.
struct UploaderRow: View {
    let owner: VideoOwner
    let card: UploaderCard?
    let staff: [StaffMember]
    let following: Bool
    let onFollow: () -> Void

    var body: some View {
        if staff.count > 1 {
            staffRow
        } else {
            single
        }
    }

    private var single: some View {
        HStack(spacing: 12) {
            RemoteImage(owner.face)
                .frame(width: Theme.Page.avatar, height: Theme.Page.avatar)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(card?.name ?? owner.name)
                    .font(Theme.Page.bodyFont)
                    .foregroundStyle(card?.isVip == true ? Theme.pink : Theme.text)
                    .lineLimit(1)
                if let card {
                    HStack(spacing: 8) {
                        Text("\(CountFormat.short(card.fans))粉丝")
                        Text("\(CountFormat.short(card.videos))视频")
                    }
                    .font(Theme.Page.smallFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            FollowPill(following: following, action: onFollow)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    private var staffRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(staff, id: \.mid) { member in
                    VStack(spacing: 3) {
                        RemoteImage(member.face)
                            .frame(width: Theme.Page.avatar, height: Theme.Page.avatar)
                            .clipShape(Circle())
                        Text(member.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text)
                        Text(member.title)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: 60)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
        }
    }
}

struct FollowPill: View {
    let following: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if !following {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                Text(following ? "已关注" : "关注")
                    .font(.system(size: 14))
            }
            .foregroundStyle(following ? Theme.secondaryText : .white)
            .frame(width: 72, height: 24)
            .background(following ? Theme.pageGrey : Theme.pink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
