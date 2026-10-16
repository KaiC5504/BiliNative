#if DEV_TOOLS
import Foundation
import MetricKit
import DevLog

/// Logs MetricKit's crash and hang diagnostics. iOS hands a crash over on a later launch, so the events land in that
/// launch's session file, not the session that crashed.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    private static let sentKey = "devtools.crashReportsSent"
    private static let sentLimit = 200
    private let queue = DispatchQueue(label: "bilinative.crash-reporter")

    static func install() {
        MXMetricManager.shared.add(shared)
        // The history also holds payloads delivered while this build had no subscriber; the sent list keeps a payload
        // from being logged on every launch.
        let past = MXMetricManager.shared.pastDiagnosticPayloads
        shared.queue.async { shared.handle(past, source: "history") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        queue.async { self.handle(payloads, source: "delivered") }
    }

    private func handle(_ payloads: [MXDiagnosticPayload], source: String) {
        var sent = UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? []
        var logged = 0
        for payload in payloads {
            let window: [String: LogValue] = [
                "from": .init(payload.timeStampBegin.timeIntervalSince1970),
                "to": .init(payload.timeStampEnd.timeIntervalSince1970),
            ]
            for crash in payload.crashDiagnostics ?? [] {
                if log(.crash, crash, window.merging(Self.fields(crash)) { _, new in new }, source: source, sent: &sent) {
                    logged += 1
                }
            }
            for hang in payload.hangDiagnostics ?? [] {
                var fields = window.merging(Self.metaFields(hang.metaData)) { _, new in new }
                fields["hangSeconds"] = .init(hang.hangDuration.converted(to: .seconds).value)
                if log(.hang, hang, fields, source: source, sent: &sent) { logged += 1 }
            }
        }
        UserDefaults.standard.set(Array(sent.suffix(Self.sentLimit)), forKey: Self.sentKey)
        Logger.shared.info(.app, "crash check", ["source": .init(source), "payloads": .init(payloads.count),
                                                 "logged": .init(logged)])
    }

    private func log(_ kind: CrashReport.Kind, _ diagnostic: MXDiagnostic & HasCallStack, _ overrides: [String: LogValue],
                     source: String, sent: inout [String]) -> Bool {
        let events = CrashReport.events(kind: kind, callStackTree: diagnostic.callStackTree.jsonRepresentation(),
                                        diagnostic: diagnostic.jsonRepresentation(), overrides: overrides)
        guard case .string(let id)? = events.first?["report"], !sent.contains(id) else { return false }
        for var fields in events {
            fields["source"] = .init(source)
            Logger.shared.log(kind == .crash ? .error : .warn, .app, kind.rawValue, fields)
        }
        sent.append(id)
        return true
    }

    private static func fields(_ crash: MXCrashDiagnostic) -> [String: LogValue] {
        var fields = metaFields(crash.metaData)
        if let value = crash.exceptionType { fields["exceptionType"] = .init(value.int64Value) }
        if let value = crash.exceptionCode { fields["exceptionCode"] = .init(value.int64Value) }
        if let value = crash.signal { fields["signal"] = .init(value.int64Value) }
        if let value = crash.terminationReason { fields["terminationReason"] = .init(value) }
        if let value = crash.virtualMemoryRegionInfo { fields["virtualMemoryRegionInfo"] = .init(value) }
        if let reason = crash.exceptionReason {
            fields["exceptionReason.exceptionName"] = .init(reason.exceptionName)
            fields["exceptionReason.className"] = .init(reason.className)
            fields["exceptionReason.composedMessage"] = .init(reason.composedMessage)
        }
        return fields
    }

    private static func metaFields(_ meta: MXMetaData) -> [String: LogValue] {
        [
            "appBuildVersion": .init(meta.applicationBuildVersion),
            "osVersion": .init(meta.osVersion),
            "deviceType": .init(meta.deviceType),
            "platformArchitecture": .init(meta.platformArchitecture),
            "isTestFlightApp": .init(meta.isTestFlightApp),
            "pid": .init(Int64(meta.pid)),
        ]
    }
}

protocol HasCallStack {
    var callStackTree: MXCallStackTree { get }
}

extension MXCrashDiagnostic: HasCallStack {}
extension MXHangDiagnostic: HasCallStack {}
#endif
