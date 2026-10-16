import Foundation
import Observation

/// What the page has put up for the actions: the coin dialog, the favourites sheet or the unfollow confirm.
/// Tests hand the page their own instance and reach the page's actions through it.
@MainActor
@Observable
final class ActionPrompts {
    enum Overlay: Equatable {
        case coin, favourites
    }

    var overlay: Overlay?
    /// The account's coins, once `coinBalance()` answers; nil while it is asked or when it failed.
    var balance: Double?
    var favourites: FavouritesModel?
    var unfollowAsked = false
    /// The page's actions for the video on screen.
    var actions: ActionsModel?

    func close() {
        overlay = nil
        favourites = nil
    }
}
