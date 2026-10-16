#if DEV_TOOLS
import Foundation
import Network
import BiliShared

enum LogTarget: Equatable {
    case service(name: String)
    case manual(host: String, port: UInt16)

    @MainActor
    init?(settings: AppSettings) {
        if !settings.logServerService.isEmpty {
            self = .service(name: settings.logServerService)
            return
        }
        let parts = settings.logServerManual.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), !parts[0].isEmpty else { return nil }
        self = .manual(host: String(parts[0]), port: port)
    }

    var endpoint: NWEndpoint {
        switch self {
        case .service(let name):
            return .service(name: name, type: "_bilinative-log._tcp", domain: "local.", interface: nil)
        case .manual(let host, let port):
            return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 47321)
        }
    }
}

/// One short HTTP/1.1 POST per batch over Network.framework, which also reaches Bonjour services
/// without resolving them to an address first.
final class LogPoster: @unchecked Sendable {
    enum Failure: Error {
        case connect(String)
        case status(String)
    }

    let target: LogTarget
    private let queue = DispatchQueue(label: "bilinative.log-poster")

    init(target: LogTarget) {
        self.target = target
    }

    func post(_ body: Data) async throws {
        let connection = NWConnection(to: target.endpoint, using: .tcp)
        defer { connection.cancel() }
        try await ready(connection)
        let head = "POST /logs HTTP/1.1\r\nHost: bilinative-log\r\nContent-Type: application/x-ndjson\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        try await send(connection, Data(head.utf8) + body)
        let reply = try await receive(connection)
        let statusLine = String(decoding: reply.prefix(64), as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        guard statusLine.contains(" 200 ") else { throw Failure.status(statusLine) }
    }

    private func ready(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Locked(false)
            @Sendable func finish(_ result: Result<Void, Error>) {
                let first = resumed.withLock { value -> Bool in
                    defer { value = true }
                    return !value
                }
                if first { continuation.resume(with: result) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed(let error): finish(.failure(Failure.connect(String(describing: error))))
                case .waiting(let error): finish(.failure(Failure.connect(String(describing: error))))
                case .cancelled: finish(.failure(Failure.connect("cancelled")))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(.failure(Failure.connect("timeout"))) }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receive(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data ?? Data()) }
            }
        }
    }
}
#endif
