import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Portrait everywhere except the landscape player.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationController.shared.mask
    }
}
