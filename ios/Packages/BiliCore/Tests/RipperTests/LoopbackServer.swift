import Foundation
import BiliShared
#if os(Windows)
import WinSDK
typealias SocketHandle = SOCKET
#else
import Darwin
typealias SocketHandle = Int32
#endif

/// A small blocking HTTP server on 127.0.0.1 (loopback only, so Windows Firewall never asks) for
/// exercising the real URLSession transport. It records which paths were requested and when the
/// client closed each connection.
final class LoopbackServer: @unchecked Sendable {
    enum Behaviour {
        /// Reads the request and never answers.
        case hang
        /// A 206 for 10 MB that sends 1 KiB every 20 ms.
        case trickle
        /// A complete 206 of this many bytes.
        case complete(Int)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let port: UInt16
    private let listener: SocketHandle
    private let routes: [String: Behaviour]
    private let stopped = Locked(false)
    private let requested = Locked<[String: Int]>([:])
    private let closed = Locked<[String: Int]>([:])

    init(routes: [String: Behaviour]) throws {
        self.routes = routes
        #if os(Windows)
        var wsa = WSADATA()
        guard WSAStartup(0x0202, &wsa) == 0 else { throw Failure(description: "WSAStartup") }
        let socketHandle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP.rawValue)
        guard socketHandle != INVALID_SOCKET else { throw Failure(description: "socket") }
        #else
        let socketHandle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketHandle >= 0 else { throw Failure(description: "socket") }
        #endif
        var address = sockaddr_in()
        address.sin_family = numericCast(AF_INET)
        #if os(Windows)
        address.sin_addr.S_un.S_addr = UInt32(0x7F00_0001).bigEndian
        #else
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        #endif
        let size = MemoryLayout<sockaddr_in>.size
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketHandle, $0, numericCast(size)) }
        }
        guard bound == 0, listen(socketHandle, 16) == 0 else {
            Self.closeSocket(socketHandle)
            throw Failure(description: "bind/listen")
        }
        var boundAddress = sockaddr_in()
        #if os(Windows)
        var length = Int32(size)
        #else
        var length = socklen_t(size)
        #endif
        _ = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketHandle, $0, &length) }
        }
        listener = socketHandle
        port = UInt16(bigEndian: boundAddress.sin_port)
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    func requests(_ path: String) -> Int { requested.current[path] ?? 0 }
    func closes(_ path: String) -> Int { closed.current[path] ?? 0 }

    func stop() {
        stopped.withLock { $0 = true }
    }

    private var isStopped: Bool { stopped.current }

    private func acceptLoop() {
        while !isStopped {
            guard Self.readable(listener, timeoutMs: 50) else { continue }
            let client = accept(listener, nil, nil)
            #if os(Windows)
            guard client != INVALID_SOCKET else { continue }
            #else
            guard client >= 0 else { continue }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            #endif
            Thread.detachNewThread { [self] in serve(client) }
        }
        Self.closeSocket(listener)
    }

    private func serve(_ client: SocketHandle) {
        defer { Self.closeSocket(client) }
        var request: [UInt8] = []
        while !request.ends(with: [13, 10, 13, 10]) {
            guard Self.readable(client, timeoutMs: 50) else {
                if isStopped { return }
                continue
            }
            guard let chunk = Self.receive(client), !chunk.isEmpty else { return }
            request += chunk
        }
        let line = String(decoding: request.prefix { $0 != 13 }, as: UTF8.self)
        let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        requested.withLock { $0[path, default: 0] += 1 }
        let sawClose: Bool
        switch routes[path] {
        case .hang:
            sawClose = waitForClose(client, pauseMs: 50) { true }
        case .trickle:
            let total = 10_000_000
            let head = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-\(total - 1)/\(total)\r\nContent-Length: \(total)\r\n\r\n"
            guard Self.send(client, Array(head.utf8)) else {
                markClosed(path)
                return
            }
            let piece = [UInt8](repeating: 0x78, count: 1024)
            sawClose = waitForClose(client, pauseMs: 20) { Self.send(client, piece) }
        case .complete(let count):
            let head = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-\(count - 1)/\(count)\r\nContent-Length: \(count)\r\nConnection: close\r\n\r\n"
            _ = Self.send(client, Array(head.utf8) + [UInt8](repeating: 0x79, count: count))
            sawClose = false
        case nil:
            _ = Self.send(client, Array("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
            sawClose = false
        }
        if sawClose { markClosed(path) }
    }

    /// Runs `step` every `pauseMs` until the client closes (true) or the server stops (false).
    /// The client sends nothing after its request, so a readable socket means it hung up.
    private func waitForClose(_ client: SocketHandle, pauseMs: Int32, step: () -> Bool) -> Bool {
        while !isStopped {
            guard step() else { return true }
            if Self.readable(client, timeoutMs: pauseMs) {
                guard let chunk = Self.receive(client), !chunk.isEmpty else { return true }
            }
        }
        return false
    }

    private func markClosed(_ path: String) {
        closed.withLock { $0[path, default: 0] += 1 }
    }

    private static func readable(_ handle: SocketHandle, timeoutMs: Int32) -> Bool {
        #if os(Windows)
        var descriptor = WSAPOLLFD(fd: handle, events: Int16(POLLRDNORM), revents: 0)
        return WSAPoll(&descriptor, 1, timeoutMs) > 0
        #else
        var descriptor = pollfd(fd: handle, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, timeoutMs) > 0
        #endif
    }

    /// nil on a socket error, empty when the peer closed.
    private static func receive(_ handle: SocketHandle) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        #if os(Windows)
        let count = buffer.withUnsafeMutableBytes { Int(recv(handle, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), 0)) }
        #else
        let count = buffer.withUnsafeMutableBytes { recv(handle, $0.baseAddress!, $0.count, 0) }
        #endif
        guard count >= 0 else { return nil }
        return Array(buffer.prefix(count))
    }

    private static func send(_ handle: SocketHandle, _ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            #if os(Windows)
            let sent = bytes[offset...].withUnsafeBytes {
                Int(WinSDK.send(handle, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), 0))
            }
            #else
            let sent = bytes[offset...].withUnsafeBytes { Darwin.send(handle, $0.baseAddress!, $0.count, 0) }
            #endif
            guard sent > 0 else { return false }
            offset += sent
        }
        return true
    }

    private static func closeSocket(_ handle: SocketHandle) {
        #if os(Windows)
        closesocket(handle)
        #else
        close(handle)
        #endif
    }
}

private extension Array where Element == UInt8 {
    func ends(with suffix: [UInt8]) -> Bool {
        count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix
    }
}
