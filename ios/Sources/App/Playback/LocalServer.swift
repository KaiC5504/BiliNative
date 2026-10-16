import Foundation
import Network
import BiliShared
import LocalHTTP
import DevLog

/// HTTP/1.1 on 127.0.0.1, one request per connection. AVPlayer fetches HLS playlists and media
/// ranges from here; media bodies stream from the BTR engine as they arrive.
final class LocalServer: @unchecked Sendable {
    enum State: Equatable {
        case stopped
        case starting
        case ready(UInt16)
        case failed(String)
    }

    let router: PlaybackRouter
    private let queue = DispatchQueue(label: "bilinative.local-server")
    private let stateBox = Locked<State>(.stopped)
    private let listenerBox = Locked<NWListener?>(nil)
    private let connections = Locked<[ObjectIdentifier: NWConnection]>([:])
    /// The task answering each connection; cancelling it ends the media body and the engine read behind it.
    private let responders = Locked<[ObjectIdentifier: Task<Void, Never>]>([:])
    private let startTask = Locked<Task<Void, Error>?>(nil)
    /// Called when a running server stops unexpectedly (or is stopped), so playback can fall back.
    var onStop: (() -> Void)?

    init(router: PlaybackRouter) {
        self.router = router
    }

    var state: State { stateBox.current }

    var isRunning: Bool {
        if case .ready = state { return true }
        return false
    }

    var port: UInt16? {
        if case .ready(let port) = state { return port }
        return nil
    }

    func url(token: String, name: String) -> URL? {
        port.flatMap { URL(string: "http://127.0.0.1:\($0)/\(token)/\(name)") }
    }

    /// Concurrent callers share one listener start.
    func start() async throws {
        if isRunning { return }
        let task = startTask.withLock { current -> Task<Void, Error> in
            if let current { return current }
            let task = Task { try await self.listen() }
            current = task
            return task
        }
        defer { startTask.withLock { if $0 == task { $0 = nil } } }
        try await task.value
    }

    private func listen() async throws {
        if isRunning { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listenerBox.withLock { $0 = listener }
        stateBox.withLock { $0 = .starting }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                // stop() clears the box before cancelling; a newer start() puts its own listener there,
                // and a superseded listener must not overwrite that one's state or report a stop.
                let isCurrent = self.listenerBox.withLock { $0 == nil || $0 === listener }
                switch state {
                case .ready:
                    // A listener stop() already let go of may still report ready; it must not mark the server running.
                    guard self.listenerBox.withLock({ $0 === listener }) else {
                        if once.claim() { continuation.resume(throwing: CancellationError()) }
                        return
                    }
                    let port = listener.port?.rawValue ?? 0
                    self.stateBox.withLock { $0 = .ready(port) }
                    Logger.shared.info(.server, "listening", ["port": .init(Int(port))])
                    if once.claim() { continuation.resume() }
                // A waiting listener may never become ready, which would leave start() hanging.
                case .failed(let error), .waiting(let error):
                    if isCurrent { self.stateBox.withLock { $0 = .failed(String(describing: error)) } }
                    Logger.shared.error(.server, "listener failed", ["error": .init(String(describing: error))])
                    // Cleared first so the cancel below does not report the failure a second time.
                    listener.stateUpdateHandler = nil
                    listener.cancel()
                    self.listenerBox.withLock { if $0 === listener { $0 = nil } }
                    if once.claim() {
                        continuation.resume(throwing: error)
                    } else if isCurrent {
                        self.onStop?()
                    }
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    Logger.shared.warn(.server, "listener stopped")
                    if isCurrent { self.stateBox.withLock { $0 = .stopped } }
                    if once.claim() {
                        continuation.resume(throwing: CancellationError())
                    } else if isCurrent {
                        self.onStop?()
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        // The cancel below ends a start in progress; a later start() must begin a new listener, not join that one.
        startTask.withLock { $0 = nil }
        let stopped = listenerBox.withLock { listener -> Bool in
            defer { listener = nil }
            listener?.cancel()
            return listener != nil
        }
        // Set now, not when the cancel is reported, so a start() right after this one opens a new listener.
        if stopped { stateBox.withLock { $0 = .stopped } }
        let open = connections.withLock { value -> [NWConnection] in
            defer { value.removeAll() }
            return Array(value.values)
        }
        let answering = responders.withLock { value -> [Task<Void, Never>] in
            defer { value.removeAll() }
            return Array(value.values)
        }
        answering.forEach { $0.cancel() }
        open.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections.withLock { $0[id] = connection }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.withLock { $0[id] = nil }
                self?.responders.withLock { $0.removeValue(forKey: id) }?.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveHead(connection, buffer: [])
    }

    private func receiveHead(_ connection: NWConnection, buffer: [UInt8]) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer += data }
            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receiveHead(connection, buffer: buffer)
                }
            case .invalid:
                Task {
                    _ = await self.send(connection, HTTPResponseWriter.head(status: 400, headers: [("Content-Length", "0"), ("Connection", "close")]))
                    connection.cancel()
                }
            case .complete(let head, _):
                let id = ObjectIdentifier(connection)
                let task = Task { await self.respond(connection, head) }
                self.responders.withLock { $0[id] = task }
                switch connection.state {
                case .failed, .cancelled:
                    // The state handler ran before the task was registered.
                    self.responders.withLock { $0.removeValue(forKey: id) }?.cancel()
                default:
                    self.watchForClose(connection, id)
                }
            }
        }
    }

    /// One request per connection, so anything the client does after the head is either a close or
    /// noise; a close means AVPlayer gave up on the request, and its engine read should stop now
    /// rather than at the next failed send.
    private func watchForClose(_ connection: NWConnection, _ id: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.responders.withLock { $0.removeValue(forKey: id) }?.cancel()
            } else {
                self.watchForClose(connection, id)
            }
        }
    }

    private func respond(_ connection: NWConnection, _ head: HTTPRequestHead) async {
        let started = Date()
        defer { connection.cancel() }
        let isHead = head.method == "HEAD"
        switch router.route(head) {
        case .text(let status, let contentType, let body):
            let headBytes = HTTPResponseWriter.head(status: status, headers: [("Content-Type", contentType),
                                                                              ("Content-Length", "\(body.count)"), ("Connection", "close")])
            _ = await send(connection, headBytes + (isHead ? [] : body))
            log(head, status: status, bytes: isHead ? 0 : Int64(body.count), firstByteMs: nil, started: started)
        case .failure(let status, let headers):
            _ = await send(connection, HTTPResponseWriter.head(status: status, headers: headers + [("Content-Length", "0"), ("Connection", "close")]))
            log(head, status: status, bytes: 0, firstByteMs: nil, started: started)
        case .media(let status, let headers, let body):
            guard await send(connection, HTTPResponseWriter.head(status: status, headers: headers + [("Connection", "close")])) else {
                log(head, status: status, bytes: 0, firstByteMs: nil, started: started)
                return
            }
            var sent: Int64 = 0
            var firstByteMs: Double?
            if !isHead {
                do {
                    for try await chunk in body {
                        if firstByteMs == nil { firstByteMs = Date().timeIntervalSince(started) * 1000 }
                        // Leaving the loop drops the stream, which cancels the engine's download.
                        guard await send(connection, chunk) else { break }
                        sent += Int64(chunk.count)
                    }
                } catch {
                    Logger.shared.warn(.server, "body failed", ["file": .init(String(head.path.split(separator: "/").last ?? "")),
                                                               "error": .init(String(describing: error)), "sent": .init(sent)])
                }
            }
            log(head, status: status, bytes: sent, firstByteMs: firstByteMs, started: started)
        }
    }

    private func send(_ connection: NWConnection, _ bytes: [UInt8]) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func log(_ head: HTTPRequestHead, status: Int, bytes: Int64, firstByteMs: Double?, started: Date) {
        var fields: [String: LogValue] = [
            "file": .init(String(head.path.split(separator: "/").last ?? "")),
            "range": .init(head.headers["range"] ?? ""),
            "status": .init(status),
            "bytes": .init(bytes),
            "ms": .init((Date().timeIntervalSince(started) * 1000).rounded()),
        ]
        if let firstByteMs { fields["firstByteMs"] = .init(firstByteMs.rounded()) }
        Logger.shared.info(.server, head.method, fields)
    }
}
