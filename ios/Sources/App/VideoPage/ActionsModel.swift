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
    /// Set when 不喜欢 needs the one-time TV-login confirmation; the page opens the sheet and clears it.
    var needsAppToken = false

    let detail: VideoDetail
    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let isLoggedIn: () -> Bool
    @ObservationIgnored private let requestLogin: () -> Void
    @ObservationIgnored private let toast: (String) -> Void
    @ObservationIgnored private let signer: AppSigner?
    @ObservationIgnored private let loadAppToken: () -> String?
    @ObservationIgnored private let clearAppToken: () -> Void
    /// What the user has changed: a late relation answer must not overwrite those, but still fills in the rest.
    @ObservationIgnored private var touched: Set<Field> = []
    @ObservationIgnored private var busy: Set<String> = []

    init(client: BiliClient, detail: VideoDetail, relation: VideoRelation?, uploader: UploaderCard?,
         isLoggedIn: @escaping () -> Bool, requestLogin: @escaping () -> Void, toast: @escaping (String) -> Void,
         signer: AppSigner? = .tv, loadAppToken: @escaping () -> String? = AppTokenStore.load,
         clearAppToken: @escaping () -> Void = AppTokenStore.delete) {
        self.client = client
        self.signer = signer
        self.loadAppToken = loadAppToken
        self.clearAppToken = clearAppToken
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
        if !touched.contains(.liked) { liked = relation.like }
        if !touched.contains(.disliked) { disliked = relation.dislike }
        if !touched.contains(.favorited) { favorited = relation.favorite }
        if !touched.contains(.following) { following = relation.attention }
        if !touched.contains(.coins) { coins = relation.coins }
    }

    private func set(_ relation: VideoRelation) {
        liked = relation.like
        disliked = relation.dislike
        favorited = relation.favorite
        following = relation.attention
        coins = relation.coins
    }

    func apply(_ uploader: UploaderCard) {
        guard !touched.contains(.following), uploader.mid == detail.owner.mid else { return }
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

    /// Whether a 三连 now goes to the server, so the row bursts only for one that does.
    var tripleSends: Bool { isLoggedIn() && !tripleDone && !busy.contains("triple") }

    // MARK: actions

    func toggleLike() async {
        let on = !liked
        await perform("like", change: {
            $0.setLiked(on)
        }, call: { client, detail in
            try await client.like(aid: detail.aid, bvid: detail.bvid, on: on)
        })
    }

    /// A build without the app keys cannot sign the call at all, so 不喜欢 stays grey there.
    var dislikeAvailable: Bool { signer != nil }

    /// Goes through the app API with the token the TV-login sheet fetched (spec 4.14). No token, or one the server
    /// no longer accepts, sends the user to the sheet instead of failing.
    func toggleDislike() async {
        guard let signer else { return toast("此版本不支持不喜欢") }
        guard isLoggedIn() else { return requestLogin() }
        guard let token = loadAppToken() else {
            needsAppToken = true
            return
        }
        let on = !disliked
        await perform("dislike", change: {
            $0.setDisliked(on)
        }, call: { client, detail in
            try await client.dislike(aid: detail.aid, on: on, accessToken: token, signer: signer)
        }, intercept: { [weak self] error in
            guard case .api(let code, _) = error as? BiliError, code == -101 || code == -2 else { return false }
            self?.clearAppToken()
            self?.needsAppToken = true
            return true
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
            toast(maxCoins == 0 ? "已投满\(detail.copyright == 2 ? 1 : 2)个硬币" : "最多还能投\(maxCoins)个硬币")
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

    private enum Field: CaseIterable {
        case liked, disliked, favorited, following, coins
    }

    private struct Snapshot {
        var liked, disliked, favorited, following: Bool
        var coins: Int
        var likeCount, coinCount, favCount: Int64

        func changed(from other: Snapshot) -> Set<Field> {
            var fields: Set<Field> = []
            if liked != other.liked { fields.insert(.liked) }
            if disliked != other.disliked { fields.insert(.disliked) }
            if favorited != other.favorited { fields.insert(.favorited) }
            if following != other.following { fields.insert(.following) }
            if coins != other.coins { fields.insert(.coins) }
            return fields
        }
    }

    private var snapshot: Snapshot {
        Snapshot(liked: liked, disliked: disliked, favorited: favorited, following: following, coins: coins,
                 likeCount: likeCount, coinCount: coinCount, favCount: favCount)
    }

    /// Takes back one action: only the fields it changed, and only those still showing its change. Actions run
    /// side by side (点赞 and 关注 sit next to each other), and one failing must not undo another.
    private func undo(from before: Snapshot, to after: Snapshot) {
        func revert<Value: Equatable>(_ field: ReferenceWritableKeyPath<ActionsModel, Value>, _ saved: KeyPath<Snapshot, Value>) {
            guard before[keyPath: saved] != after[keyPath: saved], self[keyPath: field] == after[keyPath: saved] else { return }
            self[keyPath: field] = before[keyPath: saved]
        }
        revert(\.liked, \.liked)
        revert(\.disliked, \.disliked)
        revert(\.favorited, \.favorited)
        revert(\.following, \.following)
        revert(\.coins, \.coins)
        revert(\.likeCount, \.likeCount)
        revert(\.coinCount, \.coinCount)
        revert(\.favCount, \.favCount)
    }

    /// Like clears dislike, as on the server.
    private func setLiked(_ on: Bool) {
        guard on != liked else { return }
        liked = on
        likeCount = max(0, likeCount + (on ? 1 : -1))
        if on { disliked = false }
    }

    /// Dislike takes the like back, as on the server.
    private func setDisliked(_ on: Bool) {
        disliked = on
        if on { setLiked(false) }
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
        disliked = liked ? false : before.disliked
        favorited = before.favorited || result.favorite
        favCount = before.favCount + (favorited && !before.favorited ? 1 : 0)
        let spent = result.coin ? min(result.multiply, expected) : 0
        coins = before.coins + spent
        coinCount = before.coinCount + Int64(spent)
    }

    private func perform(_ name: String, change: (ActionsModel) -> Void,
                         call: @escaping (BiliClient, VideoDetail) async throws -> Void,
                         intercept: ((Error) -> Bool)? = nil) async {
        guard isLoggedIn() else { return requestLogin() }
        guard !busy.contains(name) else { return }
        busy.insert(name)
        defer { busy.remove(name) }
        let before = snapshot
        change(self)
        let after = snapshot
        touched.formUnion(after.changed(from: before))
        do {
            try await call(client, detail)
        } catch is CancellationError {
            undo(from: before, to: after)
        } catch {
            undo(from: before, to: after)
            Logger.shared.warn(.api, "\(name) failed", ["error": .init(String(describing: error))])
            if intercept?(error) == true { return }
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
