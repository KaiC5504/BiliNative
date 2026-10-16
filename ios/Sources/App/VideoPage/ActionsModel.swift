import Foundation
import Observation
import BiliAPI
import DevLog

/// 点赞, 三连, 投币, 收藏, 分享 and 关注 for one video, shared by the page's action row and the full-screen chrome.
/// Every change shows at once and is rolled back if the server refuses it.
@MainActor
@Observable
final class ActionsModel {
    /// What a tap asks the page to put up: Task 22's coin dialog, favourites sheet and unfollow confirm, and the
    /// share sheet. The page clears it once handled.
    enum Prompt: Equatable {
        case coin, favourites, unfollow, share
    }

    private(set) var liked = false
    private(set) var disliked = false
    private(set) var favorited = false
    private(set) var following = false
    /// Coins this account has given the video.
    private(set) var coins = 0
    private(set) var likeCount: Int64
    private(set) var coinCount: Int64
    private(set) var favCount: Int64
    private(set) var shareCount: Int64
    var prompt: Prompt?

    let detail: VideoDetail
    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let isLoggedIn: () -> Bool
    @ObservationIgnored private let requestLogin: () -> Void
    @ObservationIgnored private let toast: (String) -> Void
    /// Once the user has acted, a late relation answer must not overwrite what they did.
    @ObservationIgnored private var touched = false
    @ObservationIgnored private var busy: Set<String> = []

    init(client: BiliClient, detail: VideoDetail, relation: VideoRelation?, uploader: UploaderCard?,
         isLoggedIn: @escaping () -> Bool, requestLogin: @escaping () -> Void, toast: @escaping (String) -> Void) {
        self.client = client
        self.detail = detail
        self.isLoggedIn = isLoggedIn
        self.requestLogin = requestLogin
        self.toast = toast
        likeCount = detail.stat.like
        coinCount = detail.stat.coin
        favCount = detail.stat.favorite
        shareCount = detail.stat.share
        if let relation { apply(relation) }
        if let uploader { apply(uploader) }
    }

    func apply(_ relation: VideoRelation) {
        guard !touched else { return }
        set(relation)
    }

    private func set(_ relation: VideoRelation) {
        liked = relation.like
        disliked = relation.dislike
        favorited = relation.favorite
        following = relation.attention
        coins = relation.coins
    }

    func apply(_ uploader: UploaderCard) {
        guard !touched, uploader.mid == detail.owner.mid else { return }
        following = uploader.following
    }

    /// After a login the page asks again, so the buttons show this account's state, whatever was tapped before.
    func refreshRelation() async {
        do {
            let relation = try await client.relation(aid: detail.aid, bvid: detail.bvid)
            set(relation)
        } catch {
            Logger.shared.warn(.api, "relation failed", ["error": .init(String(describing: error))])
        }
    }

    /// A repost takes one coin, an original two.
    var maxCoins: Int {
        max(0, (detail.copyright == 2 ? 1 : 2) - coins)
    }

    func canGive(_ multiply: Int, balance: Double) -> Bool {
        multiply >= 1 && multiply <= maxCoins && balance >= Double(multiply)
    }

    var tripleDone: Bool { liked && coins > 0 && favorited }

    // MARK: actions

    func toggleLike() async {
        let on = !liked
        await perform("like", change: {
            $0.setLiked(on)
        }, call: { client, detail in
            try await client.like(aid: detail.aid, bvid: detail.bvid, on: on)
        })
    }

    func triple() async {
        guard isLoggedIn() else { return requestLogin() }
        if tripleDone {
            toast("已三连")
            return
        }
        let before = snapshot
        let multiply = maxCoins
        await perform("triple", change: {
            $0.setLiked(true)
            $0.setFavorited(true)
        }, call: { client, detail in
            let result = try await client.triple(aid: detail.aid, bvid: detail.bvid)
            self.settleTriple(result, before: before, expected: multiply)
        })
    }

    func coin(_ multiply: Int, alsoLike: Bool) async {
        guard isLoggedIn() else { return requestLogin() }
        guard multiply >= 1, multiply <= maxCoins else {
            toast("已投满\(detail.copyright == 2 ? 1 : 2)个硬币")
            return
        }
        await perform("coin", change: {
            $0.coins += multiply
            $0.coinCount += Int64(multiply)
            if alsoLike { $0.setLiked(true) }
        }, call: { client, detail in
            try await client.coin(aid: detail.aid, bvid: detail.bvid, multiply: multiply, alsoLike: alsoLike)
        })
    }

    /// `inAnyFolder` is whether the video stays in some folder afterwards; only the favourites sheet knows that
    /// when it removes from one folder and keeps another. Without it, adding means favourited and removing means not.
    func applyFavourites(add: [Int64], remove: [Int64], inAnyFolder: Bool? = nil) async {
        guard !add.isEmpty || !remove.isEmpty else { return }
        let after = inAnyFolder ?? !add.isEmpty
        await perform("favourites", change: {
            $0.setFavorited(after)
        }, call: { client, detail in
            try await client.updateFavourites(aid: detail.aid, add: add, remove: remove)
        })
    }

    func toggleFollow() async {
        let on = !following
        await perform("follow", change: {
            $0.following = on
        }, call: { client, detail in
            try await client.follow(mid: detail.owner.mid, on: on)
        })
    }

    /// Counts a share the share sheet completed. Sharing needs no account, so logged out it is simply not counted.
    func shared() async {
        guard isLoggedIn() else { return }
        shareCount += 1
        do {
            try await client.countShare(aid: detail.aid)
        } catch {
            // The share itself went out; a toast about the counter would only confuse.
            shareCount -= 1
            Logger.shared.warn(.api, "share count failed", ["error": .init(String(describing: error))])
        }
    }

    // MARK: taps that open something first

    /// 关注 follows at once; 已关注 asks before unfollowing.
    func tapFollow() {
        guard isLoggedIn() else { return requestLogin() }
        if following {
            prompt = .unfollow
        } else {
            Task { await toggleFollow() }
        }
    }

    func ask(_ prompt: Prompt) {
        guard prompt == .share || isLoggedIn() else { return requestLogin() }
        self.prompt = prompt
    }

    // MARK: plumbing

    private struct Snapshot {
        var liked, disliked, favorited, following: Bool
        var coins: Int
        var likeCount, coinCount, favCount: Int64
    }

    private var snapshot: Snapshot {
        Snapshot(liked: liked, disliked: disliked, favorited: favorited, following: following, coins: coins,
                 likeCount: likeCount, coinCount: coinCount, favCount: favCount)
    }

    private func restore(_ saved: Snapshot) {
        liked = saved.liked
        disliked = saved.disliked
        favorited = saved.favorited
        following = saved.following
        coins = saved.coins
        likeCount = saved.likeCount
        coinCount = saved.coinCount
        favCount = saved.favCount
    }

    /// Like clears dislike, as on the server.
    private func setLiked(_ on: Bool) {
        guard on != liked else { return }
        liked = on
        likeCount = max(0, likeCount + (on ? 1 : -1))
        if on { disliked = false }
    }

    private func setFavorited(_ on: Bool) {
        guard on != favorited else { return }
        favorited = on
        favCount = max(0, favCount + (on ? 1 : -1))
    }

    /// The server says what 三连 actually did; the optimistic like and favourite are corrected to it and the coins
    /// it spent are added.
    private func settleTriple(_ result: TripleResult, before: Snapshot, expected: Int) {
        liked = before.liked || result.like
        likeCount = before.likeCount + (liked && !before.liked ? 1 : 0)
        if liked { disliked = false }
        favorited = before.favorited || result.favorite
        favCount = before.favCount + (favorited && !before.favorited ? 1 : 0)
        let spent = result.coin ? min(result.multiply, expected) : 0
        coins = before.coins + spent
        coinCount = before.coinCount + Int64(spent)
    }

    private func perform(_ name: String, change: (ActionsModel) -> Void,
                         call: @escaping (BiliClient, VideoDetail) async throws -> Void) async {
        guard isLoggedIn() else { return requestLogin() }
        guard !busy.contains(name) else { return }
        busy.insert(name)
        defer { busy.remove(name) }
        touched = true
        let saved = snapshot
        change(self)
        do {
            try await call(client, detail)
        } catch is CancellationError {
            restore(saved)
        } catch {
            restore(saved)
            Logger.shared.warn(.api, "\(name) failed", ["error": .init(String(describing: error))])
            if let error = error as? BiliError {
                toast(Self.message(for: error))
                if error.needsLogin { requestLogin() }
            } else {
                toast("网络连接失败，请检查网络后重试")
            }
        }
    }

    /// Bilibili words its refusals for the user (硬币不足, 已经点赞过了), so those show as sent; codes the app knows
    /// better keep `userMessage`.
    static func message(for error: BiliError) -> String {
        if case .api(let code, let message) = error, !message.isEmpty, ![-101, -352, -412, -404].contains(code) {
            return message
        }
        return error.userMessage
    }
}
