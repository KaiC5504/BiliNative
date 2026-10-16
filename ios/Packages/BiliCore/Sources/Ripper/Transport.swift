import Foundation
import BiliShared

public struct TransportResponse: Sendable {
    public let status: Int
    /// Lowercased header names.
    public let headers: [String: String]
    public let body: AsyncThrowingStream<[UInt8], Error>

    public init(status: Int, headers: [String: String], body: AsyncThrowingStream<[UInt8], Error>) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public protocol RangeTransport: Sendable {
    /// GET with `Range: bytes=start-end`. Returns once the response headers are in; the body streams.
    /// Cancelling the calling task, or dropping the body stream, must cancel the request.
    func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse

    /// How many connections the transport opens to one host; further requests to an HTTP/1.1 host wait inside it
    /// for one to free up. HTTP/2 sends every request over one connection. Nil when there is no such limit.
    var connectionsPerHost: Int? { get }
}

public extension RangeTransport {
    var connectionsPerHost: Int? { nil }
}

public enum RipperError: Error, Equatable, Sendable {
    case firstByteTimeout
    case stalled
    case attemptTimeout
    case badResponse(status: Int)
    case lengthMismatch(got: Int64, expected: Int64)
    case totalMismatch
    case noNodes
    case invalidURL
    case closed

    public var status: Int? {
        if case .badResponse(let status) = self { return status }
        return nil
    }

    public var isTimeout: Bool {
        self == .firstByteTimeout || self == .stalled || self == .attemptTimeout
    }
}
