import Observation
import SwiftUI

/// The video pages on the main navigation stack, as a path. Every way of opening a video (home, history, related
/// videos, links in comments) calls `open`, and picture in picture's restore button appends the kept page with
/// `show`, so a page always lands on top of whatever is there.
///
/// The stack's root view uses it like this:
///
///     NavigationStack(path: $navigator.path) {
///         root.videoPageDestinations()
///     }
/// What the main stack can hold. 历史记录 and 最近打开 live on the same path as video pages, so a video opened from them
/// lands on top: a view-destination push mixed with a path has no defined order.
enum AppPage: Hashable {
    case video(VideoRoute)
    case history
    case recents
}

@MainActor
@Observable
final class AppNavigator {
    var path: [AppPage] = [] {
        didSet {
            let live = Set(path.compactMap { page -> UUID? in
                if case .video(let route) = page { return route.id }
                return nil
            })
            if models.keys.contains(where: { !live.contains($0) }) {
                models = models.filter { live.contains($0.key) }
            }
        }
    }
    /// Pages pushed with a model that already exists, by route id.
    @ObservationIgnored private var models: [UUID: VideoPageModel] = [:]

    func open(_ route: VideoRoute) {
        path.append(.video(route))
    }

    func open(_ page: AppPage) {
        path.append(page)
    }

    /// Pushes a page for an existing model: the one picture in picture kept, brought back by its restore button.
    func show(_ model: VideoPageModel) {
        var route = model.route
        route.id = UUID()
        models[route.id] = model
        path.append(.video(route))
    }

    @ViewBuilder
    func page(for route: VideoRoute) -> some View {
        if let model = models[route.id] {
            VideoPageView(model: model).id(route.id)
        } else {
            VideoPageView(route: route).id(route.id)
        }
    }
}

extension View {
    /// The video page destination of the navigator's path, and the restore button of a page kept for picture in
    /// picture. Goes on the root view inside the NavigationStack bound to `AppNavigator.path`.
    func videoPageDestinations() -> some View {
        modifier(VideoPageDestinations())
    }
}

private struct VideoPageDestinations: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        let navigator = env.navigator
        let keeper = PiPKeeper.shared
        return content
            .navigationDestination(for: AppPage.self) { page in
                switch page {
                case .video(let route): navigator.page(for: route)
                case .history: HistoryView()
                case .recents: RecentsView()
                }
            }
            .onChange(of: keeper.restoring.map { ObjectIdentifier($0) }) { _, requested in
                guard requested != nil, let model = keeper.restoring else { return }
                navigator.show(model)
            }
    }
}
