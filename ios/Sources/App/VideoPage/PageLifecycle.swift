import SwiftUI
import UIKit

/// Tells a video page that is on top from one covered by a push and one that left the navigation stack.
/// SwiftUI's onDisappear fires alike for a covered page and a popped one, and onAppear can fire as a back swipe
/// starts that is then cancelled, so the page's place in its UINavigationController decides, once any
/// transition in flight has finished.
@MainActor
final class PageLifecycle {
    enum Place: Equatable {
        case top, covered, removed
    }

    private(set) var model: VideoPageModel?
    private let keeper: PiPKeeper
    private let orientation: OrientationController
    private var shown = false
    fileprivate weak var probe: UIView?
    private weak var page: UIViewController?
    private weak var navigation: UINavigationController?

    init() {
        keeper = .shared
        orientation = .shared
    }

    func appeared(_ model: VideoPageModel) {
        self.model = model
        // The first appearance is a push, which cannot be cancelled, and waiting for it would delay the start.
        guard shown else {
            shown = true
            show(model, opened: true)
            return
        }
        settle { place in
            if place == .top { self.show(model, opened: false) }
        }
    }

    func disappeared() {
        guard let model else { return }
        settle { place in
            switch place {
            case .top: break
            case .covered: self.hide(model, removed: false)
            case .removed: self.hide(model, removed: true)
            }
        }
    }

    /// SwiftUI tore the page down. A covered page popped together with the pages above it (a jump back over
    /// several pages) gets no onDisappear, so it closes here.
    fileprivate func dismantled() {
        guard let model else { return }
        hide(model, removed: true)
    }

    var place: Place {
        locate()
        guard let page, let navigation else { return probe?.window != nil ? .top : .removed }
        guard navigation.viewControllers.contains(page) else { return .removed }
        let visible = navigation.topViewController === page && page.viewIfLoaded?.window != nil
        return visible ? .top : .covered
    }

    private func show(_ model: VideoPageModel, opened: Bool) {
        model.presenter = self
        let resume = keeper.pageShown(model, opened: opened)
        orientation.begin(owner: model, videoIsVertical: model.detail?.isVertical ?? false)
        model.appear(resuming: resume)
    }

    private func hide(_ model: VideoPageModel, removed: Bool) {
        // A page brought back from the small window has its own lifecycle; this one's late teardown is not its.
        guard model.presenter === self else { return }
        orientation.end(owner: model)
        if removed {
            keeper.pageRemoved(model)
        } else {
            model.cover()
        }
    }

    private func settle(_ body: @escaping @MainActor (Place) -> Void) {
        locate()
        guard let coordinator = page?.transitionCoordinator ?? navigation?.transitionCoordinator else {
            body(place)
            return
        }
        var done = false
        let finish = {
            guard !done else { return }
            done = true
            body(self.place)
        }
        let queued = coordinator.animate(alongsideTransition: nil) { _ in
            MainActor.assumeIsolated { finish() }
        }
        if !queued { finish() }
    }

    private func locate() {
        var responder: UIResponder? = probe
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.parent as? UINavigationController {
                page = controller
                self.navigation = navigation
                return
            }
            responder = current.next
        }
    }

    fileprivate func probeMoved(to window: UIWindow?) {
        if window != nil { locate() }
    }
}

/// An empty view inside the page that finds the page's controller and reports SwiftUI tearing the page down.
struct PageProbe: UIViewRepresentable {
    let lifecycle: PageLifecycle

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.lifecycle = lifecycle
        lifecycle.probe = view
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {}

    static func dismantleUIView(_ view: ProbeView, coordinator: ()) {
        view.lifecycle?.dismantled()
    }

    final class ProbeView: UIView {
        /// Strong: SwiftUI may drop the page's state before it dismantles this view.
        var lifecycle: PageLifecycle?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isHidden = true
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            lifecycle?.probeMoved(to: window)
        }
    }
}
