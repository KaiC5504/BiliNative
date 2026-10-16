#if DEBUG
import Foundation
import Network
import BiliShared
import BiliAPI
import DevLog
import LocalHTTP
import Ripper

/// Helpers for the simulator tests, compiled into Debug builds only. The test target links no
/// engine modules of its own, so engine values are built here inside the app module.
enum DebugSupport {
    static func makeRouter() -> PlaybackRouter { PlaybackRouter() }

    static func staticContent(size: Int, range: ClosedRange<Int>) -> [UInt8] {
        range.map { UInt8(truncatingIfNeeded: $0 &* 13) }
    }

    /// master.m3u8 plus a media file "v.mp4" whose first 100 bytes come from memory.
    static func registerStaticAssets(on server: LocalServer, size: Int, onRead: (@Sendable () -> Void)? = nil) -> String {
        let all = staticContent(size: size, range: 0...(size - 1))
        let media = MediaResource(totalSize: Int64(size), prefix: Array(all[0..<100])) { range in
            onRead?()
            return AsyncThrowingStream { continuation in
                continuation.yield(Array(all[Int(range.start)...Int(range.end)]))
                continuation.finish()
            }
        }
        return server.router.register(PlaybackAssets(playlists: ["master.m3u8": "#EXTM3U\n"], media: ["v.mp4": media]))
    }

    /// "hang.mp4": every read starts (`onRead`) but never yields; `onEnd` fires when the read stream is torn down.
    static func registerHangingAsset(on server: LocalServer, onRead: @escaping @Sendable () -> Void,
                                     onEnd: @escaping @Sendable () -> Void) -> String {
        let media = MediaResource(totalSize: 10_000, prefix: []) { _ in
            onRead()
            return AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in onEnd() }
            }
        }
        return server.router.register(PlaybackAssets(playlists: [:], media: ["hang.mp4": media]))
    }

    /// ftyp, optionally a moov, then a version 0 sidx with one 1000-byte, 2-second reference. The moov is
    /// empty, or holds one HEVC sample entry of type `videoEntry` with VPS, SPS and PPS. Both tracks of the
    /// choice point at the same layout, each with a primary address on primary.invalid and one backup per
    /// host in `backupHosts`.
    static func headerFixture(withMoov: Bool, backupHosts: [String] = ["backup.invalid"], videoEntry: String? = nil,
                              videoCodecs: String = "avc1.640032") -> (choice: TrackChoice, bytes: [UInt8], total: Int64) {
        func uint32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) } }
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] { uint32(8 + payload.count) + Array(type.utf8) + payload }
        func sampleEntry(_ type: String) -> [UInt8] {
            let parameterSets = [UInt8(32), 33, 34].flatMap { nal -> [UInt8] in [nal, 0, 1, 0, 2, 0xAA, 0xBB] }
            let hvcC = box("hvcC", [UInt8](repeating: 0, count: 22) + [3] + parameterSets)
            let stsd = box("stsd", uint32(0) + uint32(1) + box(type, [UInt8](repeating: 0, count: 78) + hvcC))
            return box("trak", box("mdia", box("minf", box("stbl", stsd))))
        }
        let ftyp = box("ftyp", Array("isom".utf8) + uint32(0))
        let moov = withMoov ? box("moov", videoEntry.map(sampleEntry) ?? []) : []
        let sidx = box("sidx", uint32(0) + uint32(1) + uint32(1000) + uint32(0) + uint32(0) + [0, 0, 0, 1]
                                + uint32(1000) + uint32(2000) + uint32(0))
        let initEnd = Int64(ftyp.count + moov.count) - 1
        let bytes = ftyp + moov + sidx
        let total = Int64(bytes.count) + 1000
        func stream(_ id: Int, _ codecs: String) -> DashStream {
            DashStream(id: id, baseURL: "https://primary.invalid/upgcxcode/\(id).m4s?deadline=1&upsig=sig",
                       backupURLs: backupHosts.map { "https://\($0)/upgcxcode/\(id).m4s?deadline=1&upsig=sig" }, bandwidth: 1_000_000,
                       mimeType: "video/mp4", codecs: codecs, codecid: 7, width: 1920, height: 1080, frameRate: "30",
                       initialization: ByteRange(start: 0, end: initEnd)!,
                       indexRange: ByteRange(start: initEnd + 1, end: Int64(bytes.count) - 1)!)
        }
        return (TrackChoice(video: stream(80, videoCodecs), audio: stream(30280, "mp4a.40.2")), bytes, total)
    }

    enum FixtureAnswer: Sendable {
        case refuse
        case wholeFile
        case wrongRange
    }

    /// Serves `bytes` as the start of a `total`-byte file. Hosts in `answers` misbehave instead:
    /// 403, 200 with the whole file, or 206 labelled with a range one byte off.
    struct FixtureTransport: RangeTransport {
        let bytes: [UInt8]
        let total: Int64
        let answers: [String: FixtureAnswer]

        func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
            func body(_ chunk: [UInt8]) -> AsyncThrowingStream<[UInt8], Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(chunk)
                    continuation.finish()
                }
            }
            guard range.start < Int64(bytes.count) else {
                return TransportResponse(status: 416, headers: ["content-range": "bytes */\(total)"], body: body([]))
            }
            let slice = Array(bytes[Int(range.start)...Int(min(range.end, Int64(bytes.count) - 1))])
            switch answers[url.host ?? ""] {
            case .refuse:
                return TransportResponse(status: 403, headers: [:], body: body([]))
            case .wholeFile:
                return TransportResponse(status: 200, headers: ["content-length": "\(total)"], body: body(bytes))
            case .wrongRange:
                return TransportResponse(status: 206, headers: ["content-range": "bytes \(range.start + 1)-\(range.end + 1)/\(total)"],
                                         body: body(slice))
            case nil:
                return TransportResponse(status: 206, headers: ["content-range": "bytes \(range.start)-\(range.end)/\(total)"],
                                         body: body(slice))
            }
        }
    }
}

/// Serves files from a directory with Range support, like a CDN node, on 127.0.0.1. Paths under
/// /refused/ answer 403, like a primary address an account may not use on any node.
final class FakeCDNServer: @unchecked Sendable {
    struct Request: Sendable {
        let path: String
        let range: String
        /// Sent by the engine's transport (FixturePlayback marks it); AVPlayer's own requests are not.
        let engine: Bool
        let status: Int
    }

    static let clientHeader = "X-Fixture-Client"
    let directory: URL
    private let listenerBox = Locked<NWListener?>(nil)
    private let queue = DispatchQueue(label: "bilinative.fake-cdn")
    private let log = Locked<[Request]>([])
    private let files = Locked<[String: Data]>([:])
    private let refusingEngineMedia = Locked(false)

    init(directory: URL) {
        self.directory = directory
    }

    var requests: [Request] { log.current }
    var requestCount: Int { log.current.count }

    /// The engine's media ranges answer 403 while its header requests (from byte 0) still work, so
    /// BTR mode fails mid-playback and direct mode can still start.
    func refuseEngineMedia(_ refuse: Bool) {
        refusingEngineMedia.withLock { $0 = refuse }
    }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listenerBox.withLock { $0 = listener }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: [])
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let resumed = Locked(false)
            @Sendable func resumeOnce(_ result: Result<UInt16, Error>) {
                let first = resumed.withLock { value -> Bool in
                    defer { value = true }
                    return !value
                }
                if first { continuation.resume(with: result) }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(.success(listener.port?.rawValue ?? 0))
                // A waiting listener may never become ready, which would leave start() hanging.
                case .failed(let error), .waiting(let error):
                    listener.stateUpdateHandler = nil
                    listener.cancel()
                    resumeOnce(.failure(error))
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    resumeOnce(.failure(CancellationError()))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listenerBox.withLock { listener in
            listener?.cancel()
            listener = nil
        }
    }

    private func receive(_ connection: NWConnection, buffer: [UInt8]) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            let buffer = buffer + (data.map { [UInt8]($0) } ?? [])
            switch HTTPRequestParser.parse(buffer) {
            case .incomplete where !isComplete && error == nil:
                self.receive(connection, buffer: buffer)
            case .complete(let head, _):
                self.respond(connection, head)
            default:
                connection.cancel()
            }
        }
    }

    private func content(_ name: String) -> Data? {
        if let cached = files.current[name] { return cached }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        files.withLock { $0[name] = data }
        return data
    }

    private func respond(_ connection: NWConnection, _ head: HTTPRequestHead) {
        let engine = head.headers[Self.clientHeader.lowercased()] == "engine"
        var status: Int
        var headers: [(String, String)] = []
        var body = Data()
        if let content = content(String(head.path.split(separator: "/").last ?? "")) {
            let total = Int64(content.count)
            switch RangeRequest.parse(head.headers["range"], totalSize: total) {
            case .full:
                status = 200
                body = content
            case .range(let range):
                status = engine && range.start > 0 && refusingEngineMedia.current ? 403 : 206
                body = content.subdata(in: Int(range.start)..<Int(range.end + 1))
                headers.append(("Content-Range", "bytes \(range.start)-\(range.end)/\(total)"))
            case .unsatisfiable:
                status = 416
            }
            if head.path.hasPrefix("/refused/") { status = 403 }
        } else {
            status = 404
        }
        if status >= 400 {
            headers = []
            body = Data()
        }
        log.withLock { $0.append(Request(path: head.path, range: head.headers["range"] ?? "", engine: engine, status: status)) }
        let headBytes = HTTPResponseWriter.head(status: status, headers: headers + [
            ("Content-Type", "video/mp4"), ("Content-Length", "\(body.count)"), ("Connection", "close"),
        ])
        connection.send(content: Data(headBytes) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct FixtureMedia {
    struct Track: Decodable {
        let file: String
        let codecs: String
        let bandwidth: Int
        let width: Int
        let height: Int
        let initialization: String
        let indexRange: String
        let size: Int
    }

    let video: Track
    let audio: Track

    static func load(directory: URL, variant: String) throws -> FixtureMedia {
        let data = try Data(contentsOf: directory.appendingPathComponent("meta.json"))
        let all = try JSONDecoder().decode([String: [String: AnyDecodableTrack]].self, from: data)
        guard let entry = all[variant], let video = entry["video"]?.track, let audio = entry["audio"]?.track else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return FixtureMedia(video: video, audio: audio)
    }

    /// meta.json mixes track objects with a plain "duration" number.
    struct AnyDecodableTrack: Decodable {
        let track: Track?
        init(from decoder: Decoder) throws {
            track = try? Track(from: decoder)
        }
    }
}

/// Keeps the player's log events, so a test can tell which path playback took. The test target
/// cannot import DevLog, so fields arrive as plain strings.
final class CapturingLogSink: LogSink, @unchecked Sendable {
    struct Entry: Sendable {
        let message: String
        let fields: [String: String]
    }

    private let store = Locked<[Entry]>([])

    var entries: [Entry] { store.current }

    func start() {
        Logger.shared.add(self)
    }

    func stop() {
        Logger.shared.remove(self)
    }

    func receive(_ event: LogEvent) {
        guard event.cat == .player else { return }
        let fields = event.f.mapValues { value -> String in
            switch value {
            case .string(let text): return text
            case .int(let number): return String(number)
            case .double(let number): return String(number)
            case .bool(let flag): return String(flag)
            }
        }
        store.withLock { $0.append(Entry(message: event.msg, fields: fields)) }
    }
}

final class FixtureProvider: PlayURLProvider, @unchecked Sendable {
    let info: PlayURLInfo
    private let count = Locked(0)

    init(info: PlayURLInfo) {
        self.info = info
    }

    var calls: Int { count.current }

    func playURL(quality: Int) async throws -> PlayURLInfo {
        count.withLock { $0 += 1 }
        return info
    }
}

enum FixturePlayback {
    /// A PlaybackEnvironment whose "Bilibili" is the fixture media on the fake CDN nodes at `ports`.
    /// With `refusedPrimary` the primary address is one every node refuses, and the backups (one per
    /// node) are the only working addresses.
    static func make(media: FixtureMedia, codecid: Int, ports: [UInt16], server: LocalServer, router: PlaybackRouter,
                     loader: DirectPlaylistLoader, refusedPrimary: Bool = false) -> PlaybackEnvironment {
        func address(_ port: UInt16, _ path: String) -> String {
            "http://127.0.0.1:\(port)/\(path)?deadline=4102444800"
        }
        func stream(_ track: FixtureMedia.Track, id: Int, codecid: Int) -> DashStream {
            let primary = address(ports[0], refusedPrimary ? "refused/\(track.file)" : track.file)
            let backups = (refusedPrimary ? ports : Array(ports.dropFirst())).map { address($0, track.file) }
            return DashStream(id: id, baseURL: primary, backupURLs: backups,
                              bandwidth: track.bandwidth, mimeType: "video/mp4", codecs: track.codecs, codecid: codecid,
                              width: track.width, height: track.height, frameRate: "30",
                              initialization: ByteRange.parse(track.initialization)!, indexRange: ByteRange.parse(track.indexRange)!)
        }
        let dash = Dash(duration: 40, video: [stream(media.video, id: 64, codecid: codecid)], audio: [stream(media.audio, id: 30280, codecid: 0)])
        let info = PlayURLInfo(quality: 64, acceptQuality: [64], acceptDescription: ["测试 360P"], dash: dash, hasDurl: false)
        var config = RipperConfig()
        config.fixedConcurrency = 8
        return PlaybackEnvironment(provider: FixtureProvider(info: info), router: router, server: server, directLoader: loader,
                                   transport: URLSessionRangeTransport(headers: [FakeCDNServer.clientHeader: "engine"]),
                                   directTransport: URLSessionRangeTransport(headers: [FakeCDNServer.clientHeader: "engine"]),
                                   auto: AutoConcurrency(), nodeMode: .custom(ports.map { NodeAddress(host: "127.0.0.1", port: Int($0)) }),
                                   policy: loopbackPolicy(ports: ports), ripperConfig: config,
                                   codecMemory: CodecMemory(defaults: UserDefaults(suiteName: "fixture-\(UUID().uuidString)")!),
                                   mediaHeaders: [:])
    }

    /// Stands in for the production policy, which only lets signed addresses go to Bilibili's https media hosts.
    static func loopbackPolicy(ports: [UInt16]) -> MediaURLPolicy {
        let allowed = Set(ports.map(Int.init))
        return MediaURLPolicy { url in
            url.scheme == "http" && url.host == "127.0.0.1" && url.port.map(allowed.contains) == true
        }
    }
}
#endif
