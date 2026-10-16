import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BiliShared

/// Streams range responses through URLSession's delegate callbacks, which work the same with
/// Apple's Foundation and with swift-corelibs-foundation on Windows.
public final class URLSessionRangeTransport: NSObject, RangeTransport, URLSessionDataDelegate, @unchecked Sendable {
    private final class Handler {
        var response: CheckedContinuation<TransportResponse, Error>?
        // Handed over with the response and not kept here: a caller that drops the body must cancel the request.
        var body: AsyncThrowingStream<[UInt8], Error>?
        let bodyContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
        // Set when this transport cancelled the task; any other URLError.cancelled is passed on as is.
        var abandoned = false

        init(response: CheckedContinuation<TransportResponse, Error>) {
            self.response = response
            let pair = AsyncThrowingStream<[UInt8], Error>.makeStream()
            body = pair.stream
            bodyContinuation = pair.continuation
        }
    }

    private let handlers = Locked<[Int: Handler]>([:])
    private let headers: [String: String]
    private var session: URLSession!
    public let connectionsPerHost: Int?

    public init(headers: [String: String] = [:], maxConnectionsPerHost: Int = 8) {
        self.headers = headers
        connectionsPerHost = maxConnectionsPerHost
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = maxConnectionsPerHost
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    public func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue(range.headerValue, forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TransportResponse, Error>) in
                let handler = Handler(response: continuation)
                handler.bodyContinuation.onTermination = { [handlers, weak handler] _ in
                    handlers.withLock { _ in handler?.abandoned = true }
                    task.cancel()
                }
                handlers.withLock { $0[task.taskIdentifier] = handler }
                // onCancel may have run before the handler existed.
                if Task.isCancelled {
                    abandon(task)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            abandon(task)
        }
    }

    /// Ends the call at once rather than when URLSession reports the cancellation, so a cancelled hedge
    /// copy gives its connection permit back immediately instead of after the first-byte timeout.
    private func abandon(_ task: URLSessionDataTask) {
        let removed = remove(task.taskIdentifier)
        task.cancel()
        if let removed { Self.end(removed, error: CancellationError()) }
    }

    private struct Removed {
        let handler: Handler
        let pending: CheckedContinuation<TransportResponse, Error>?
        let abandoned: Bool
    }

    private func remove(_ id: Int) -> Removed? {
        handlers.withLock { map in
            guard let handler = map.removeValue(forKey: id) else { return nil }
            let pending = handler.response
            handler.response = nil
            return Removed(handler: handler, pending: pending, abandoned: handler.abandoned)
        }
    }

    private static func end(_ removed: Removed, error: Error?) {
        let handler = removed.handler
        if let pending = removed.pending {
            pending.resume(throwing: error ?? RipperError.badResponse(status: 0))
        } else if let error {
            handler.bodyContinuation.finish(throwing: error)
        } else {
            handler.bodyContinuation.finish()
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (name, value) in http?.allHeaderFields ?? [:] {
            if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
        }
        let ready = handlers.withLock { map -> (CheckedContinuation<TransportResponse, Error>, AsyncThrowingStream<[UInt8], Error>)? in
            guard let handler = map[dataTask.taskIdentifier], let continuation = handler.response,
                  let body = handler.body else { return nil }
            handler.response = nil
            handler.body = nil
            return (continuation, body)
        }
        if let ready {
            ready.0.resume(returning: TransportResponse(status: http?.statusCode ?? 0, headers: headers, body: ready.1))
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let handler = handlers.withLock { $0[dataTask.taskIdentifier] }
        handler?.bodyContinuation.yield([UInt8](data))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let removed = remove(task.taskIdentifier) else { return }
        let cancelledHere = removed.abandoned && (error as? URLError)?.code == .cancelled
        Self.end(removed, error: cancelledHere ? CancellationError() : error)
    }
}
