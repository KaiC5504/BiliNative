import Foundation
import DevLog

@MainActor
enum DevLogSetup {
    private static var fileSink: FileSink?
    private static var networkSink: NetworkSink?
    #if DEV_TOOLS
    private static var appliedTarget: LogTarget?
    private static let ackStore = AckStore(url: directory.appendingPathComponent("ack.json"))
    #endif
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("logs")
    }

    /// The on-phone log is always kept (last 20 MB), so the export button works even without a PC.
    static func install() {
        guard fileSink == nil else { return }
        if let sink = try? FileSink(directory: directory, session: Logger.shared.session) {
            Logger.shared.add(sink)
            fileSink = sink
        }
        Logger.shared.info(.app, "launch", DeviceInfo.fields())
        DeviceInfo.watchNetwork()
        #if DEV_TOOLS
        CrashReporter.install()
        #endif
    }

    static func apply(_ settings: AppSettings) {
        #if DEV_TOOLS
        let wanted = settings.logServerEnabled ? LogTarget(settings: settings) : nil
        // A new sink replays every unsent file, so an unchanged target keeps the running one.
        if networkSink != nil, wanted == appliedTarget { return }
        if let networkSink {
            networkSink.stop()
            Logger.shared.remove(networkSink)
        }
        networkSink = nil
        appliedTarget = nil
        guard let target = wanted else { return }
        let poster = LogPoster(target: target)
        let sink = NetworkSink(poster: { try await poster.post($0) })
        let ack = ackStore
        sink.onAcknowledged = { session, seq in ack.record(session, seq) }
        let session = Logger.shared.session
        // Read before the sink joins: once it posts, the watermark moves past events only the file holds.
        let confirmed = ack.lastSeq(session)
        let cut = Logger.shared.add(sink)
        networkSink = sink
        appliedTarget = target
        Logger.shared.info(.app, "log server on", ["target": .init(String(describing: target))])
        guard let fileSink else {
            sink.start()
            return
        }
        // Up to 20 MB of files: decoded off the main actor, and the sink starts only once the backlog sits ahead of
        // the live events, so acknowledgements stay in seq order.
        let limit = sink.maxBuffered
        Task.detached(priority: .utility) {
            fileSink.flush()
            let backlog = ReplayPlanner.unsent(files: fileSink.sessionFiles(), currentSession: session, ack: ack,
                                               current: (after: confirmed, through: cut), limit: limit)
            sink.prepend(backlog)
            await MainActor.run {
                if DevLogSetup.networkSink === sink { sink.start() }
            }
        }
        #endif
    }

    static func networkState(_ settings: AppSettings) -> String {
        #if DEV_TOOLS
        if settings.logServerEnabled, LogTarget(settings: settings) == nil {
            return settings.logServerManual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请选择电脑，或输入 IP:端口" : "地址无效，格式为 IP:端口"
        }
        #endif
        guard let networkSink else { return "未开启" }
        switch networkSink.state {
        case .idle: return "连接中…"
        case .connected: return "已连接，待发送 \(networkSink.pending) 条"
        case .failing(let reason): return "连不上：\(reason)"
        }
    }

    static func exportFile() -> URL? {
        try? fileSink?.exportFile()
    }

    static func clearFiles() {
        fileSink?.removeAllFiles()
    }
}
