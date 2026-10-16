#if DEV_TOOLS
import Foundation
import Network
import Observation

@MainActor
@Observable
final class LogServerDiscovery {
    private(set) var services: [String] = []
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_bilinative-log._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            }
            Task { @MainActor in self?.services = Array(Set(names)).sorted() }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
#endif
