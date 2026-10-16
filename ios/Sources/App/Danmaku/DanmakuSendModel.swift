import Foundation
import Observation
import BiliAPI
import DevLog

/// The look of the next danmaku the user sends; kept for the life of the page.
struct DanmakuStyle: Equatable {
    var fontSize = 25
    var mode = 1
    var color: UInt32 = 0xFFFFFF
    /// The 大会员 gradient. The server wants it together with white.
    var gradient = false

    static let defaultFontSize = 25
    static let smallFontSize = 18

    /// White, then the colours of the official picker in its order (23). The 会员 gradient chip sits
    /// between white and red and is not a colour value.
    static let colors: [UInt32] = [
        0xFFFFFF, 0xD42D25, 0xFCF150, 0x42954C, 0x469DE4, 0xCF2C7D,
        0x9AC143, 0x0F2D6E, 0xE6AE48, 0x613C77, 0x91BEC9, 0x8E7A43,
    ]
}

@MainActor
@Observable
final class DanmakuSendModel {
    static let maxLength = 100

    var text = "" {
        didSet {
            if text.count > Self.maxLength { text = String(text.prefix(Self.maxLength)) }
        }
    }
    var style = DanmakuStyle()
    private(set) var sending = false
    /// The page presents login when this turns true, and resets it once it has.
    var needsLogin = false

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let page: VideoPageModel
    @ObservationIgnored private let danmaku: DanmakuController
    @ObservationIgnored private let isVip: () -> Bool
    @ObservationIgnored private let isLoggedIn: () -> Bool

    init(client: BiliClient, page: VideoPageModel, danmaku: DanmakuController,
         isVip: @escaping () -> Bool, isLoggedIn: @escaping () -> Bool) {
        self.client = client
        self.page = page
        self.danmaku = danmaku
        self.isVip = isVip
        self.isLoggedIn = isLoggedIn
    }

    var canSend: Bool { !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var vip: Bool { isVip() }

    var loggedIn: Bool { isLoggedIn() }

    /// Posts the draft. Returns the message to show, or nil when it went out (or there was nothing to send).
    func send() async -> String? {
        guard isLoggedIn() else {
            needsLogin = true
            return "需要登录"
        }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return nil }
        guard !danmaku.closed else { return "UP主已关闭弹幕" }
        guard !style.gradient || isVip() else { return "开通大会员后可使用" }
        guard let item = page.current else { return "视频还没有加载好" }
        let progress = Int64(((page.controller?.position ?? 0) * 1000).rounded())
        let draft = DanmakuDraft(cid: item.cid, bvid: item.bvid, text: message, mode: style.mode, fontSize: style.fontSize,
                                 color: style.gradient ? 0xFFFFFF : style.color, gradient: style.gradient, progressMs: progress)
        sending = true
        defer { sending = false }
        do {
            _ = try await client.postDanmaku(draft)
        } catch is CancellationError {
            return nil
        } catch let error as BiliError {
            Logger.shared.warn(.api, "danmaku post failed", ["error": .init(String(describing: error))])
            return failureMessage(error)
        } catch {
            Logger.shared.warn(.api, "danmaku post failed", ["error": .init(String(describing: error))])
            return "发送失败，请检查网络后重试"
        }
        danmaku.showOwn(draft)
        text = ""
        return nil
    }

    private func failureMessage(_ error: BiliError) -> String {
        if error.needsLogin {
            needsLogin = true
            return "需要登录"
        }
        // Bilibili words its refusals for the user (frequency, banned words, level); show them as sent.
        if case .api(_, let message) = error, !message.isEmpty { return message }
        return error.userMessage
    }
}
