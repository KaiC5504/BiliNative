import SwiftUI
import UIKit
import BiliAPI
import AppLogic

/// One comment as in 10 and 13: avatar, name and badges, rich text, pictures, the meta line, and in the list the
/// preview box of replies.
struct CommentRow: View {
    let comment: Comment
    let model: CommentsModel
    /// The preview box shows only in the list; a thread's root and replies leave it out (13).
    var showsReplies = true
    var showsDivider = true
    let onReply: (Comment) -> Void
    var onOpenThread: (Comment) -> Void = { _ in }
    @State private var confirmingDelete = false

    private typealias T = Theme.Comments

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CommentAvatar(member: comment.member)
                .frame(width: T.textLeading - T.avatarLeading, alignment: .leading)
                .padding(.leading, T.avatarLeading)
            VStack(alignment: .leading, spacing: 0) {
                nameLine
                content
                    .padding(.top, 2)
                if !comment.pictures.isEmpty {
                    CommentPictures(pictures: comment.pictures) { index in
                        model.viewing = PictureViewing(pictures: comment.pictures, index: index)
                    }
                    .padding(.top, 8)
                }
                CommentMeta(comment: comment, isOwn: model.isOwn(comment),
                            onReply: { onReply(comment) },
                            onLike: { Task { await model.toggleLike(comment) } },
                            onHate: { Task { await model.toggleHate(comment) } },
                            onDelete: { confirmingDelete = true })
                    .padding(.top, 6)
                if showsReplies {
                    if comment.upLiked {
                        UpLikedLabel()
                            .padding(.top, 4)
                    }
                    if comment.replyCount > 0 || !comment.previewReplies.isEmpty {
                        ReplyPreview(comment: comment) { onOpenThread(comment) }
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                }
            }
            .padding(.trailing, T.trailing)
            .padding(.bottom, 8)
        }
        .padding(.top, T.rowTop)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let image = comment.member.fanCardImage {
                FanCard(image: image, number: comment.member.fanCardNumber, color: T.color(css: comment.member.fanCardColor))
                    .padding(.top, 3)
                    .padding(.trailing, T.fanCardTrailing)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1 / 3)
                    .padding(.leading, T.textLeading - 2)
            }
        }
        .alert("删除评论", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) { Task { await model.delete(comment) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除这条评论吗？")
        }
    }

    private var nameLine: some View {
        HStack(spacing: 6) {
            Text(comment.member.name)
                .font(T.nameFont)
                .foregroundStyle(comment.member.isVip ? T.vipName : T.name)
                .lineLimit(1)
            LevelBadge(level: comment.member.level)
            if comment.member.mid == model.upMid, model.upMid != 0 {
                UpBadge()
            }
        }
        // Clear of the fan card, which sits higher at the right.
        .padding(.trailing, comment.member.fanCardImage == nil ? 0 : T.fanCard.width + T.fanCardTrailing - T.trailing)
        .frame(height: 18)
    }

    private var content: some View {
        let runs = comment.root == 0 ? comment.runs : RichTextView.markingReplyTarget(comment.runs)
        return RichTextView(runs: runs,
                            prefix: comment.isPinned ? Text("\(Text(Image(uiImage: PinnedTag.image)).baselineOffset(-2)) ") : nil)
            .fixedSize(horizontal: false, vertical: true)
            .contextMenu {
                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.message }
            }
    }
}

/// The avatar, the pendant frame around it, and the pink 大 for 大会员.
struct CommentAvatar: View {
    let member: CommentMember

    private typealias T = Theme.Comments

    var body: some View {
        let framed = member.pendant != nil
        let side = framed ? T.pendantAvatar : T.avatar
        RemoteImage(member.face)
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay {
                if let pendant = member.pendant {
                    DecorImage(url: pendant, height: side * T.pendantScale)
                        .frame(width: side * T.pendantScale, height: side * T.pendantScale)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if member.isVip {
                    Text("大")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: T.vipBadge - 2, height: T.vipBadge - 2)
                        .background(Theme.pink, in: Circle())
                        .padding(1)
                        .background(.white, in: Circle())
                        .offset(x: 1, y: 2)
                }
            }
            .frame(width: T.avatar, height: T.avatar)
            .accessibilityHidden(true)
    }
}

struct UpBadge: View {
    var body: some View {
        Text("UP")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(height: LevelBadge.size.height)
            .background(Theme.pink, in: RoundedRectangle(cornerRadius: 2))
    }
}

/// The fan card's art with its number over the right half (10, 13).
struct FanCard: View {
    let image: String
    let number: String?
    let color: Color?

    var body: some View {
        DecorImage(url: image, height: Theme.Comments.fanCard.height)
            .frame(width: Theme.Comments.fanCard.width, height: Theme.Comments.fanCard.height, alignment: .leading)
            .overlay(alignment: .leading) {
                if let number {
                    FanNumber(number: number, color: color ?? Theme.Comments.fanNumber)
                        .padding(.leading, 31)
                }
            }
    }
}

struct UpLikedLabel: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 10))
            Text("UP主觉得很赞")
                .font(Theme.Comments.metaFont)
        }
        .foregroundStyle(Theme.Comments.header)
    }
}

/// One picture large, more in a 3-column grid (10).
struct CommentPictures: View {
    let pictures: [CommentPicture]
    let onOpen: (Int) -> Void

    private typealias T = Theme.Comments
    /// Single pictures in 10: a tall one 162 pt wide and cut at 3:4; a wide one gets more width.
    private static let tallWidth: CGFloat = 162
    private static let wideWidth: CGFloat = 240
    private static let tallestRatio: CGFloat = 4 / 3
    private static let flattestRatio: CGFloat = 9 / 16

    var body: some View {
        if pictures.count == 1, let picture = pictures.first {
            let ratio = picture.width > 0 && picture.height > 0 ? picture.height / picture.width : 1
            let width = ratio >= 1 ? Self.tallWidth : Self.wideWidth
            let height = width * min(max(ratio, Self.flattestRatio), Self.tallestRatio)
            cell(0, pixels: Int(width * 3))
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: T.pictureRadius))
        } else {
            VStack(spacing: T.pictureSpacing) {
                ForEach(Array(stride(from: 0, to: pictures.count, by: 3)), id: \.self) { start in
                    HStack(spacing: T.pictureSpacing) {
                        ForEach(start..<(start + 3), id: \.self) { index in
                            if index < pictures.count {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { cell(index, pixels: 360) }
                                    .clipShape(RoundedRectangle(cornerRadius: T.pictureRadius))
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ index: Int, pixels: Int) -> some View {
        Button {
            onOpen(index)
        } label: {
            RemoteImage(Self.thumbnail(pictures[index].url, width: pixels))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("图片\(index + 1)")
    }

    /// Bilibili's image servers scale on request ("@480w.webp"); the viewer still loads the original.
    static func thumbnail(_ url: String, width: Int) -> String {
        guard url.contains("hdslb.com/bfs/"), !url.contains("@") else { return url }
        return "\(url)@\(width)w.webp"
    }
}

/// "1小时前 湖北  回复" at the left; 👍 count, 👎 and ⋮ at the right.
struct CommentMeta: View {
    let comment: Comment
    let isOwn: Bool
    let onReply: () -> Void
    let onLike: () -> Void
    let onHate: () -> Void
    let onDelete: () -> Void

    private typealias T = Theme.Comments

    var body: some View {
        let liked = comment.action == 1
        let hated = comment.action == 2
        HStack(spacing: 0) {
            Text(stamp)
                .font(T.metaFont)
                .foregroundStyle(T.meta)
                .lineLimit(1)
            Button(action: onReply) {
                Text("回复")
                    .font(T.actionFont)
                    .foregroundStyle(T.action)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 8)
            Button(action: onLike) {
                HStack(spacing: 5) {
                    Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(T.thumbFont)
                    if comment.likes > 0 {
                        Text(CountFormat.short(comment.likes))
                            .font(T.actionFont)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(liked ? Theme.pink : T.action)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(liked ? "取消点赞" : "点赞")
            Button(action: onHate) {
                Image(systemName: hated ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(T.thumbFont)
                    .foregroundStyle(hated ? Theme.pink : T.action)
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 13)
            .accessibilityLabel(hated ? "取消踩" : "踩")
            Menu {
                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.message }
                if isOwn {
                    Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(T.action)
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 9)
            .accessibilityLabel("更多")
        }
        .buttonStyle(.plain)
        .frame(height: T.metaHeight)
        // ⋮ sits closer to the edge than the text column ends (10).
        .padding(.trailing, -6)
    }

    private var stamp: String {
        let time = TimeFormat.relative(comment.ctime, now: Date())
        guard let location = comment.location else { return time }
        return "\(time) \(location)"
    }
}

/// The grey box under a comment: up to two replies and "共N条回复 >" (10, 12). Any tap opens the thread.
struct ReplyPreview: View {
    let comment: Comment
    let onOpen: () -> Void

    private typealias T = Theme.Comments

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(comment.previewReplies.prefix(2)) { reply in
                    line(reply)
                }
                if comment.replyCount > 0 {
                    HStack(spacing: 4) {
                        Text("共\(comment.replyCount)条回复")
                            .font(T.moreFont)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.link)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.previewBox, in: RoundedRectangle(cornerRadius: T.boxRadius))
            .contentShape(RoundedRectangle(cornerRadius: T.boxRadius))
        }
        .buttonStyle(.plain)
    }

    private func line(_ reply: Comment) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            RichTextView(runs: RichTextView.markingReplyTarget(reply.runs), font: T.previewFont, fontSize: T.previewSize,
                         color: T.previewText, lineSpacing: 5, lineLimit: 2,
                         prefix: Text("\(Text(verbatim: reply.member.name + ": ").foregroundStyle(T.name))"))
                .layoutPriority(1)
            if reply.likes > 0 {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1, height: 10)
                    .padding(.horizontal, 7)
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 13))
                    Text(CountFormat.short(reply.likes))
                        .font(T.actionFont)
                }
                .foregroundStyle(T.action)
                .fixedSize()
            }
        }
    }
}
