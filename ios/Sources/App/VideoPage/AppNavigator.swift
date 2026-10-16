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
@MainActor
@Observable
final class AppNavigator {
    var path: [VideoRoute] = [] {
        didSet {
            let live = Set(path.map(\.id))
            if models.keys.contains(where: { !live.contains($0) }) {
                models = models.filter { live.contains($0.key) }
            }
        }
    }
    /// Pages pushed with a model that already exists, by route id.
    @ObservationIgnored private var models: [UUID: VideoPageModel] = [:]

    func open(_ route: VideoRoute) {
        path.append(route)
    }

    /// Pushes a page for an existing model: the one picture in picture kept, brought back by its restore button.
    func show(_ model: VideoPageModel) {
        var route = model.route
        route.id = UUID()
        models[route.id] = model
        path.append(route)
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
            .navigationDestination(for: VideoRoute.self) { navigator.page(for: $0) }
            .onChange(of: keeper.restoring.map { ObjectIdentifier($0) }) { _, requested in
                guard requested != nil, let model = keeper.restoring else { return }
                navigator.show(model)
            }
    }
}
