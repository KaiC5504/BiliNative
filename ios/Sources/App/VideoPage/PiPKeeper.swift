import Observation
import SwiftUI
import DevLog

/// Holds the video page that was closed while picture in picture plays it, as the official app does: the small
/// window goes on, its restore button brings the same page back (no reload, same position), and its ✕ ends it.
/// One video at a time: any other page that shows stops the kept one first.
@MainActor
@Observable
final class PiPKeeper {
    static let shared = PiPKeeper()

    private(set) var kept: VideoPageModel?
    /// The kept page the restore button asked for; the restorer on screen pushes it.
    private(set) var restoring: VideoPageModel?

    /// A page left its navigation stack: kept while picture in picture plays it, closed otherwise.
    func pageRemoved(_ model: VideoPageModel) {
        guard model.pipActive else {
            model.close()
            return
        }
        guard kept !== model else { return }
        release()
        kept = model
        model.continueInPiP()
        Logger.shared.info(.ui, "kept for picture in picture", ["bvid": .init(model.current?.bvid ?? model.route.bvid)])
    }

    /// Every page reports here when it shows; the answer is whether it may resume its own playback. The kept
    /// page is handed back to its page. A page that opens stops any other kept one first. A page uncovered by
    /// going back leaves the small window playing and stays paused until it is played, which stops the window.
    func pageShown(_ model: VideoPageModel, opened: Bool) -> Bool {
        guard let kept else { return true }
        if kept === model {
            self.kept = nil
            restoring = nil
            return true
        }
        guard opened else { return false }
        release()
        return true
    }

    /// Called before a page plays: one video at a time.
    func willPlay(_ model: VideoPageModel) {
        guard let kept, kept !== model else { return }
        release()
    }

    /// The restore button of the kept page's window; false when nothing will show the page again.
    func restore(_ model: VideoPageModel) -> Bool {
        guard kept === model else { return false }
        restoring = model
        return true
    }

    func pipStopped(_ model: VideoPageModel) {
        guard kept === model else { return }
        guard restoring === model else {
            release()
            return
        }
        // A restore normally shows the page before the window finishes closing; this covers it arriving late,
        // or never (completion false).
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.kept === model else { return }
            self.release()
        }
    }

    /// Stops and releases the kept page.
    func release() {
        guard let model = kept else { return }
        kept = nil
        restoring = nil
        model.close()
    }
}

/// A page that can be pushed by `navigationDestination(item:)`: models compare by identity.
struct KeptPage: Hashable {
    let model: VideoPageModel

    static func == (lhs: KeptPage, rhs: KeptPage) -> Bool { lhs.model === rhs.model }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(model)) }
}

extension View {
    /// Pushes the page picture in picture kept when its window's restore button is tapped. Belongs on the root
    /// of a navigation stack that can be on screen while a page is kept (home).
    func restoresKeptVideoPage() -> some View {
        modifier(KeptPageRestorer())
    }
}

private struct KeptPageRestorer: ViewModifier {
    @State private var page: KeptPage?

    func body(content: Content) -> some View {
        let keeper = PiPKeeper.shared
        return content
            .navigationDestination(item: $page) { VideoPageView(model: $0.model) }
            .onChange(of: keeper.restoring.map { ObjectIdentifier($0) }) { _, requested in
                guard requested != nil, let model = keeper.restoring else { return }
                page = KeptPage(model: model)
            }
    }
}
