import Foundation
import Observation
import BiliAPI
import DevLog

extension AppSigner {
    /// Nil in a build made without the BILI_APP_KEYS secret.
    static var tv: AppSigner? {
        AppKeys.tv.map { AppSigner(appKey: $0.key, appSecret: $0.secret) }
    }
}

/// The one-time TV-login confirmation that yields the app token 不喜欢 needs (spec 4.14): ask for an auth code,
/// let the user confirm it in a signed-in web view, poll until the token arrives.
@MainActor
@Observable
final class TVLoginModel {
    enum State: Equatable {
        case unavailable, starting, confirming(url: URL), expired, done, failed(String)
    }

    private(set) var state: State = .starting

    @ObservationIgnored private let client: BiliClient
    @ObservationIgnored private let signer: AppSigner?
    @ObservationIgnored private let sleep: (Double) async -> Void
    /// A retry or cancel makes an older loop that is still awaiting the network stand down.
    @ObservationIgnored private var generation = 0

    private static let pollInterval = 2.0
    private static let tolerableNetworkFailures = 5

    init(client: BiliClient, signer: AppSigner?,
         sleep: @escaping (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.client = client
        self.signer = signer
        self.sleep = sleep
    }

    /// Runs until the code is confirmed, expires, fails or is cancelled.
    func start() async {
        guard let signer else {
            state = .unavailable
            return
        }
        generation += 1
        let mine = generation
        state = .starting
        let code: (url: String, authCode: String)
        do {
            code = try await client.tvAuthCode(signer: signer)
        } catch {
            return fail(error, mine)
        }
        guard mine == generation, !Task.isCancelled else { return }
        guard let url = URL(string: code.url), url.scheme == "https" else {
            return fail(BiliError.decoding("tv login: bad confirm url"), mine)
        }
        state = .confirming(url: url)

        var networkFailures = 0
        while true {
            await sleep(Self.pollInterval)
            guard mine == generation, !Task.isCancelled else { return }
            do {
                switch try await client.tvPoll(signer: signer, authCode: code.authCode) {
                case .waiting:
                    networkFailures = 0
                case .expired:
                    guard mine == generation else { return }
                    Logger.shared.info(.app, "tv login expired")
                    state = .expired
                    return
                case .confirmed(let token, _):
                    guard mine == generation else { return }
                    if AppTokenStore.save(token) {
                        Logger.shared.info(.app, "tv login done")
                        state = .done
                    } else {
                        state = .failed("无法保存授权")
                    }
                    return
                }
            } catch is CancellationError {
                return
            } catch let error as BiliError {
                return fail(error, mine)
            } catch {
                // A dropped connection while the user is still confirming should not end the attempt.
                networkFailures += 1
                if networkFailures >= Self.tolerableNetworkFailures { return fail(error, mine) }
            }
        }
    }

    func cancel() {
        generation += 1
    }

    private func fail(_ error: Error, _ mine: Int) {
        guard mine == generation else { return }
        Logger.shared.warn(.app, "tv login failed", ["error": .init(String(describing: error))])
        if let error = error as? BiliError {
            state = .failed(ActionsModel.message(for: error))
        } else {
            state = .failed("网络连接失败，请检查网络后重试")
        }
    }
}
