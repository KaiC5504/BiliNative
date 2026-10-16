import Observation
import DevLog

/// Holds the video page that was closed while picture in picture plays it, as the official app does: the small
/// window goes on, its restore button brings the same page back (no reload, same position), and its ✕ ends it.
/// One video at a time: any other page that shows stops the kept one first.
@MainActor
@Observable
final class PiPKeeper {
    static let shared = PiPKeeper()

    private(set) var kept: VideoPageModel?
    /// The kept page the restore button asked for, until its page shows.
    private(set) var restoring: VideoPageModel?
    /// The page whose video is in the small window, kept or still on its page.
    @ObservationIgnored private(set) weak var inPiP: VideoPageModel?

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
    /// Going back can show the page below before the popped page in the small window is reported removed, so the
    /// answer follows whichever page has picture in picture, kept yet or not.
    func pageShown(_ model: VideoPageModel, opened: Bool) -> Bool {
        if let kept, kept === model {
            self.kept = nil
            restoring = nil
            return true
        }
        if opened {
            release()
            return true
        }
        if let inPiP, inPiP !== model { return false }
        return kept == nil
    }

    /// Called before a page plays: one video at a time.
    func willPlay(_ model: VideoPageModel) {
        guard let kept, kept !== model else { return }
        release()
    }

    /// The restore button of the kept page's window: the page goes back on top of the stack it was on. False when
    /// nothing will show the page again.
    func restore(_ model: VideoPageModel) -> Bool {
        guard kept === model, let navigator = model.navigator else { return false }
        restoring = model
        navigator.show(model)
        return true
    }

    func pipStarted(_ model: VideoPageModel) {
        inPiP = model
    }

    func pipStopped(_ model: VideoPageModel) {
        if inPiP === model { inPiP = nil }
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
        if inPiP === model { inPiP = nil }
        model.close()
    }
}
