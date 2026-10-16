import Foundation
import DevLog

@MainActor
enum DevLogSetup {
    private static var fileSink: FileSink?
    private static var networkSink: NetworkSink?
    #if DEV_TOOLS
    private static var appliedTarget: LogTarget?
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
        let ack = AckStore(url: directory.appendingPathComponent("ack.json"))
        sink.onAcknowledged = { session, seq in ack.record(session, seq) }
        if let fileSink {
            // Whatever an earlier (perhaps crashed) session never got to the PC goes first.
            sink.enqueue(ReplayPlanner.unsent(files: fileSink.sessionFiles(), currentSession: Logger.shared.session, ack: ack))
        }
        Logger.shared.add(sink)
        sink.start()
        networkSink = sink
        appliedTarget = target
        Logger.shared.info(.app, "log server on", ["target": .init(String(describing: target))])
        #endif
    }

    static func networkState() -> String {
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
