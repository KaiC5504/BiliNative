import Foundation

public enum BiliHosts {
    /// bilibili.com or any subdomain; a plain suffix test would also accept "evilbilibili.com".
    /// Cookie domains arrive with a leading dot, hence the trim.
    public static func isBilibili(_ host: String) -> Bool {
        var name = host.lowercased()
        if name.hasPrefix(".") { name.removeFirst() }
        return name == "bilibili.com" || name.hasSuffix(".bilibili.com")
    }
}
