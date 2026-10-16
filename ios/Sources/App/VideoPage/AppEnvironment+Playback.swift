import AVFoundation
import Foundation
import AppLogic
import Danmaku

extension AppEnvironment {
    func makeController(for item: PlayItem, player: AVPlayer) -> PlaybackControlling {
        #if DEBUG
        if DemoFixtures.isEnabled { return DemoPlayback(player: player) }
        #endif
        return PlaybackController(environment: playbackEnvironment(bvid: item.bvid, cid: item.cid), quality: settings.preferredQuality,
                                  codec: settings.preferredCodec, btrEnabled: settings.btrEnabled, player: player)
    }

    /// The environment lives as long as the app, so the page's closures may hold it.
    func makeVideoPageModel(route: VideoRoute) -> VideoPageModel {
        VideoPageModel(route: route, client: client, settings: settings, blockRules: blockRules,
                       account: { self.account },
                       makeController: { self.makeController(for: $0, player: $1) },
                       ownHash: { self.mid.map { MidHash.of(uid: $0) } })
    }
}
