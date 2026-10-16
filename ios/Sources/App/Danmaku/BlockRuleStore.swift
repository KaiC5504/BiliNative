import Foundation
import Observation
import BiliAPI
import Danmaku
import DevLog

/// The account's synced 弹幕屏蔽词. One store lives in `AppEnvironment`, so every video page shares the list
/// and a rule added in one page filters the next page's danmaku at once.
@MainActor
@Observable
final class BlockRuleStore {
    enum RuleError: Error, Equatable {
        case empty
        case invalidUser
        case duplicate
        case invalidRegex

        var message: String {
            switch self {
            case .empty: return "请输入内容"
            case .invalidUser: return "请输入正确的用户 UID"
            case .duplicate: return "已经在屏蔽列表里了"
            case .invalidRegex: return "正则表达式有误"
            }
        }
    }

    static let cacheSeconds: TimeInterval = 600

    private(set) var rules: [BlockRule] = []

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var inflight: Task<Void, Never>?
    /// Bumped by `clear`, so an answer that was already on its way when the user logged out is dropped.
    @ObservationIgnored private var generation = 0

    init(client: BiliClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    /// The video page asks on every open; the cache keeps that to one request per ten minutes.
    func refresh(force: Bool = false) async {
        guard client.csrf != nil else {
            clear()
            return
        }
        if !force, let lastSuccess, now().timeIntervalSince(lastSuccess) < Self.cacheSeconds { return }
        if let inflight {
            await inflight.value
            return
        }
        let task = Task { await fetch() }
        inflight = task
        await task.value
        inflight = nil
    }

    private func fetch() async {
        let started = generation
        do {
            let fetched = try await client.danmakuBlockRules()
            guard started == generation else { return }
            rules = fetched
            lastSuccess = now()
        } catch is CancellationError {
            return
        } catch let error as BiliError where error.needsLogin {
            // The cookies exist but Bilibili no longer accepts them.
            guard started == generation else { return }
            rules = []
            lastSuccess = nil
        } catch {
            Logger.shared.warn(.api, "block rules failed", ["error": .init(String(describing: error))])
        }
    }

    /// For a user rule the typed text is a uid, and Bilibili matches the CRC-32 of it that rides on each danmaku.
    func add(_ kind: BlockRule.Kind, filter: String) async throws {
        let text = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RuleError.empty }
        let stored: String
        if kind == .user {
            if let uid = Int64(text), uid > 0 {
                stored = MidHash.of(uid: uid)
            } else if text.count <= 8, text.allSatisfy(\.isHexDigit) {
                stored = text.lowercased()
            } else {
                throw RuleError.invalidUser
            }
        } else {
            if kind == .regex {
                var pattern = text
                if pattern.count >= 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
                    pattern = String(pattern.dropFirst().dropLast())
                }
                guard !pattern.isEmpty, (try? NSRegularExpression(pattern: pattern)) != nil else {
                    throw RuleError.invalidRegex
                }
            }
            stored = text
        }
        guard !rules.contains(where: { $0.kind == kind && $0.filter == stored }) else { throw RuleError.duplicate }
        let generation = self.generation
        let rule = try await client.addBlockRule(kind, filter: stored)
        guard generation == self.generation else { return }
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
    }

    func delete(_ rule: BlockRule) async throws {
        let generation = self.generation
        try await client.deleteBlockRule(id: rule.id)
        guard generation == self.generation else { return }
        rules.removeAll { $0.id == rule.id }
    }

    func clear() {
        generation += 1
        rules = []
        lastSuccess = nil
    }
}
