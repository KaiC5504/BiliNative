import Foundation
import AppLogic

extension AppEnvironment {
    func makeController(for item: PlayItem) -> PlaybackControlling {
        #if DEBUG
        if DemoFixtures.isEnabled { return DemoPlayback() }
        #endif
        return PlaybackController(environment: playbackEnvironment(bvid: item.bvid, cid: item.cid), quality: settings.preferredQuality,
                                  codec: settings.preferredCodec, btrEnabled: settings.btrEnabled)
    }

    /// The environment lives as long as the app, so the page's closures may hold it.
    func makeVideoPageModel(route: VideoRoute) -> VideoPageModel {
        VideoPageModel(route: route, client: client, settings: settings,
                       account: { self.account },
                       makeController: { self.makeController(for: $0) })
    }
}
