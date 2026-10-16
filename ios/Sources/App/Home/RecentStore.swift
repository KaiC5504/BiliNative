import Foundation
import Observation

struct PlayerRoute: Hashable, Codable, Identifiable {
    let bvid: String
    let cid: Int64
    let title: String
    let part: String
    let page: Int
    let pageCount: Int

    var id: String { "\(bvid)#\(cid)" }
}

@MainActor
@Observable
final class RecentStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "home.recents"
    private(set) var items: [PlayerRoute]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([PlayerRoute].self, from: $0) } ?? []
    }

    func add(_ route: PlayerRoute) {
        items.removeAll { $0.id == route.id }
        items.insert(route, at: 0)
        if items.count > 30 { items.removeLast(items.count - 30) }
        defaults.set(try? JSONEncoder().encode(items), forKey: key)
    }

    func clear() {
        items = []
        defaults.removeObject(forKey: key)
    }
}
