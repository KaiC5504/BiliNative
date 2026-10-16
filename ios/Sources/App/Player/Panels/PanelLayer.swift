import SwiftUI

enum PlayerPanel: Identifiable {
    case quality, codec, speed, more, episodes, danmakuSettings

    var id: Self { self }
}

/// The pickers and panels over the player. Task 11 fills them in; until then nothing opens.
struct PanelLayer: View {
    @Binding var panel: PlayerPanel?
    let model: VideoPageModel

    var body: some View {
        Color.clear.allowsHitTesting(false)
    }
}
