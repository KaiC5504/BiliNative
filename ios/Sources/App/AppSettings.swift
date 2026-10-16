import Foundation
import Observation
import BiliAPI
import Ripper
import AppLogic

@MainActor
@Observable
final class AppSettings {
    enum NodeChoice: String, CaseIterable, Identifiable {
        case overseas, mainland

        var id: String { rawValue }
        var label: String { self == .overseas ? "海外节点" : "大陆节点" }
        var mode: NodeMode { self == .overseas ? .overseas : .mainland }
    }

    private enum Keys {
        static let node = "settings.node"
        static let quality = "settings.quality"
        static let codec = "settings.codec"
        static let btr = "settings.btr"
        static let overlay = "settings.overlay"
        static let logEnabled = "settings.log.enabled"
        static let logManual = "settings.log.manual"
        static let logService = "settings.log.service"
        static let autoplay = "player.autoplay"
        static let loop = "player.loop"
        static let fit = "player.fit"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var nodeChoice: NodeChoice { didSet { defaults.set(nodeChoice.rawValue, forKey: Keys.node) } }
    /// Bilibili quality id; 120 is 4K, 80 is 1080P.
    var preferredQuality: Int { didSet { defaults.set(preferredQuality, forKey: Keys.quality) } }
    var preferredCodec: VideoCodec { didSet { defaults.set(preferredCodec.rawValue, forKey: Keys.codec) } }
    var btrEnabled: Bool { didSet { defaults.set(btrEnabled, forKey: Keys.btr) } }
    var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Keys.overlay) } }
    var logServerEnabled: Bool { didSet { defaults.set(logServerEnabled, forKey: Keys.logEnabled) } }
    /// "192.168.1.5:47321"; used when no Bonjour service is chosen.
    var logServerManual: String { didSet { defaults.set(logServerManual, forKey: Keys.logManual) } }
    /// Name of the chosen Bonjour service, or "" for the manual address.
    var logServerService: String { didSet { defaults.set(logServerService, forKey: Keys.logService) } }
    /// 自动连播: the next part or 合集 episode plays when a video ends.
    var autoplay: Bool { didSet { defaults.set(autoplay, forKey: Keys.autoplay) } }
    var loop: LoopMode { didSet { defaults.set(loop.rawValue, forKey: Keys.loop) } }
    var fit: FitMode { didSet { defaults.set(fit.rawValue, forKey: Keys.fit) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        nodeChoice = NodeChoice(rawValue: defaults.string(forKey: Keys.node) ?? "") ?? .overseas
        preferredQuality = defaults.object(forKey: Keys.quality) as? Int ?? 120
        preferredCodec = VideoCodec(rawValue: defaults.string(forKey: Keys.codec) ?? "") ?? .hevc
        btrEnabled = defaults.object(forKey: Keys.btr) as? Bool ?? true
        showOverlay = defaults.object(forKey: Keys.overlay) as? Bool ?? true
        logServerEnabled = defaults.object(forKey: Keys.logEnabled) as? Bool ?? false
        logServerManual = defaults.string(forKey: Keys.logManual) ?? ""
        logServerService = defaults.string(forKey: Keys.logService) ?? ""
        autoplay = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        loop = LoopMode(rawValue: defaults.string(forKey: Keys.loop) ?? "") ?? LoopMode.none
        fit = FitMode(rawValue: defaults.string(forKey: Keys.fit) ?? "") ?? FitMode.fit
    }
}
