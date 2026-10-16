import Observation
import SwiftUI

/// A page on the main navigation stack.
enum AppPage: Hashable {
    case video(VideoRoute)
    case history
    case recents
}

/// The main navigation stack, as a path. Every way of opening a video (home, history, related videos, links in
/// comments) calls `open`, and picture in picture's restore button appends the kept page with `show`, so a page
/// always lands on top of whatever is there. 历史记录 and 最近打开 go on the same path: a view destination mixed
/// with a typed path has no defined order.
///
/// The stack's root view uses it like this:
///
///     NavigationStack(path: $navigator.path) {
///         root.videoPageDestinations(history: { HistoryView() }, recents: { RecentsView() })
///     }
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

    func open(_ page: AppPage) {
        path.append(page)
    }

    func open(_ route: VideoRoute) {
        open(.video(route))
    }

    /// Pushes a page for an existing model: the one picture in picture kept, brought back by its restore button.
    func show(_ model: VideoPageModel) {
        var route = model.route
        route.id = UUID()
        models[route.id] = model
        open(.video(route))
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
    /// The destinations of the navigator's path, and the restore button of a page kept for picture in picture.
    /// Goes on the root view inside the NavigationStack bound to `AppNavigator.path`; the home screen supplies
    /// the 历史记录 and 最近打开 pages.
    func videoPageDestinations<History: View, Recents: View>(@ViewBuilder history: @escaping () -> History,
                                                             @ViewBuilder recents: @escaping () -> Recents) -> some View {
        modifier(AppPageDestinations(history: history, recents: recents))
    }

    /// Without 历史记录 and 最近打开 pages: those two show nothing.
    func videoPageDestinations() -> some View {
        videoPageDestinations(history: { EmptyView() }, recents: { EmptyView() })
    }
}

private struct AppPageDestinations<History: View, Recents: View>: ViewModifier {
    let history: () -> History
    let recents: () -> Recents
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        let navigator = env.navigator
        let keeper = PiPKeeper.shared
        return content
            .navigationDestination(for: AppPage.self) { page in
                switch page {
                case .video(let route): navigator.page(for: route)
                case .history: history()
                case .recents: recents()
                }
            }
            .onChange(of: keeper.restoring.map { ObjectIdentifier($0) }) { _, requested in
                guard requested != nil, let model = keeper.restoring else { return }
                navigator.show(model)
            }
    }
}
