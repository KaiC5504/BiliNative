import SwiftUI
import UIKit
import BiliAPI

/// A comment's pictures full screen over the whole page, swiping between them. An overlay rather than a presented
/// controller, so nothing is handed to UIKit while the page may rotate. A tap closes it.
struct PictureViewer: View {
    let viewing: PictureViewing
    let onClose: () -> Void
    @State private var index: Int

    init(viewing: PictureViewing, onClose: @escaping () -> Void) {
        self.viewing = viewing
        self.onClose = onClose
        _index = State(initialValue: viewing.index)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Comments.viewerBackground
                .ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(viewing.pictures.indices, id: \.self) { position in
                    ViewerPage(picture: viewing.pictures[position])
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            if viewing.pictures.count > 1 {
                Text("\(index + 1)/\(viewing.pictures.count)")
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Comments.viewerText)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .statusBarHidden()
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }
}

private struct ViewerPage: View {
    let picture: CommentPicture
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Comments.viewerText.opacity(0.5))
            } else {
                ProgressView()
                    .tint(Theme.Comments.viewerText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: picture.url) {
            guard let url = ImageLoader.secureURL(picture.url) else {
                failed = true
                return
            }
            if let loaded = await ImageLoader.shared.image(for: url) {
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            } else {
                failed = true
            }
        }
    }
}
