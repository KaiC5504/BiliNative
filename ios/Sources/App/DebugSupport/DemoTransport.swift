#if DEBUG
import Foundation
import BiliAPI

/// Answers every request from `DemoFixtures`, so demo screens and screenshots need no network or login.
final class DemoTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (status, body) = DemoFixtures.response(for: request.url, method: request.method)
        return HTTPResponse(status: status, headers: ["content-type": "application/json"], body: body, finalURL: request.url)
    }
}
#endif
