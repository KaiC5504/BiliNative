import Foundation
import BiliShared
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable {
    public var url: URL
    public var headers: [String: String]
    public var method: String
    public var body: Data?

    public init(url: URL, headers: [String: String] = [:], method: String = "GET", body: Data? = nil) {
        self.url = url
        self.headers = headers
        self.method = method
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    /// Lowercased header names.
    public var headers: [String: String]
    public var body: Data
    /// After redirects, which is how b23.tv short links are resolved.
    public var finalURL: URL

    public init(status: Int, headers: [String: String], body: Data, finalURL: URL) {
        self.status = status
        self.headers = headers
        self.body = body
        self.finalURL = finalURL
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        // Cookies are managed by CookieJar; URLSession's own store would send stale ones.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration, delegate: RedirectCookieGuard(), delegateQueue: nil)
    }

    /// The Cookie header is set by hand, so URLSession would forward it to whatever host a redirect points at.
    /// A 307/308 also keeps the method and body, which can be a form carrying the csrf token.
    static func redirectedRequest(_ request: URLRequest) -> URLRequest {
        guard !BiliHosts.isBilibili(request.url?.host ?? "") else { return request }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Cookie")
        stripped.httpBody = nil
        stripped.httpBodyStream = nil
        return stripped
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let pending = Locked<URLSessionDataTask?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        let dropped = (error as? URLError)?.code == .cancelled
                        continuation.resume(throwing: dropped ? CancellationError() : error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: BiliError.http(0))
                        return
                    }
                    var headers: [String: String] = [:]
                    for (name, value) in http.allHeaderFields {
                        if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
                    }
                    continuation.resume(returning: HTTPResponse(status: http.statusCode, headers: headers, body: data ?? Data(),
                                                                finalURL: http.url ?? request.url))
                }
                pending.withLock { $0 = task }
                // onCancel may have run before the task existed.
                if Task.isCancelled { task.cancel() }
                task.resume()
            }
        } onCancel: {
            pending.current?.cancel()
        }
    }
}

private final class RedirectCookieGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(URLSessionHTTPTransport.redirectedRequest(request))
    }
}
