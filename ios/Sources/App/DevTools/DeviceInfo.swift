import Foundation
import Network
import UIKit
import DevLog

enum DeviceInfo {
    private static var monitor: NWPathMonitor?

    /// A Wi-Fi to cellular switch mid-playback explains a burst of failed pieces in the logs.
    @MainActor
    static func watchNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let type = path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.cellular) ? "cellular" : "other"
            Logger.shared.info(.app, "network", ["type": .init(type), "up": .init(path.status == .satisfied)])
        }
        monitor.start(queue: DispatchQueue(label: "bilinative.network"))
        self.monitor = monitor
    }

    @MainActor
    static func fields() -> [String: LogValue] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ["app": .init(AppInfo.version), "ios": .init(UIDevice.current.systemVersion), "model": .init(model)]
    }
}
