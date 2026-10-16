import SwiftUI

/// Fills whatever frame it is given; the caller sets the size or aspect ratio.
struct RemoteImage: View {
    private struct Loaded {
        let url: URL
        let image: UIImage
    }

    private let url: URL?
    private let contentMode: ContentMode
    @State private var loaded: Loaded?

    init(_ url: String?, contentMode: ContentMode = .fill) {
        self.url = url.flatMap(ImageLoader.secureURL)
        self.contentMode = contentMode
    }

    var body: some View {
        Theme.pageGrey
            .overlay {
                if let loaded, loaded.url == url {
                    Image(uiImage: loaded.image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { return }
                guard let image = await ImageLoader.shared.image(for: url) else { return }
                withAnimation(.easeOut(duration: 0.15)) { loaded = Loaded(url: url, image: image) }
            }
    }
}
