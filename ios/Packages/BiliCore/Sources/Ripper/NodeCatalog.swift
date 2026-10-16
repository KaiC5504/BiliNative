import Foundation

public struct NodeAddress: Hashable, Sendable {
    public let host: String
    public let port: Int?

    public init(host: String, port: Int? = nil) {
        self.host = host.lowercased()
        self.port = port
    }
}

public enum NodeMode: Equatable, Sendable {
    case mainland
    case overseas
    /// Explicit nodes, as BTR's custom mode; the simulator integration test also uses it for localhost nodes.
    case custom([NodeAddress])
}

public struct MediaURLPolicy: Sendable {
    public let allowsURL: @Sendable (URL) -> Bool

    public init(allowsURL: @escaping @Sendable (URL) -> Bool) {
        self.allowsURL = allowsURL
    }

    /// Signed download addresses are only ever sent to Bilibili's own media hosts.
    public static let bilibili = MediaURLPolicy { url in
        let text = url.absoluteString
        // URL and URLComponents read a backslash differently, so the host the policy checks
        // could differ from the one the rest of the catalog uses.
        guard !text.contains("\\"), let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.percentEncodedHost?.lowercased(),
              host == url.host?.lowercased(),
              NodeCatalog.isPlainHostName(host) else { return false }
        let path = components.percentEncodedPath.lowercased()
        guard path.hasSuffix(".m4s") || path.hasSuffix(".mp4") || path.hasSuffix(".flv") else { return false }
        return NodeCatalog.mediaHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static let any = MediaURLPolicy { _ in true }
}

public enum NodeCatalog {
    public static let mainland = [
        "upos-sz-mirrorali.bilivideo.com",
        "upos-sz-mirrorhw.bilivideo.com",
        "upos-sz-mirrorbos.bilivideo.com",
        "upos-sz-mirror08c.bilivideo.com",
        "upos-sz-mirrorbd.bilivideo.com",
        "upos-sz-mirror14b.bilivideo.com",
        "upos-sz-estgoss.bilivideo.com",
        "upos-sz-mirrorcos.bilivideo.com",
    ]

    public static let overseas = [
        "upos-sz-mirrorcosov.bilivideo.com",
        "upos-sz-mirroraliov.bilivideo.com",
        "cn-hk-eq-01-01.bilivideo.com",
        "cn-hk-eq-01-03.bilivideo.com",
    ]

    static let mediaHostSuffixes = [
        "bilivideo.com", "bilivideo.cn", "bilivideo.net", "akamaized.net", "szbdyd.com",
        "hdslb.com", "xycdn.com", "mountaintoys.cn", "nexusedgeio.com", "ahdohpiechei.com",
    ]

    /// BTR `normalizeCdnHost`'s shape check: letters, digits and hyphens in dot-separated labels,
    /// so no percent escapes, userinfo, port or trailing dot.
    static func isPlainHostName(_ host: String) -> Bool {
        host.range(of: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", options: .regularExpression) != nil
    }

    public static func host(of url: String) -> String {
        URLComponents(string: url)?.host?.lowercased() ?? ""
    }

    public static func nodeKey(of url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return "" }
        return components.port.map { "\(host):\($0)" } ?? host
    }

    /// The signed address without its node: the same address can be asked of any node.
    public static func address(of url: String) -> String {
        guard let components = URLComponents(string: url) else { return "" }
        return components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    public static func isAkamai(_ url: String) -> Bool {
        host(of: url).hasSuffix(".akamaized.net")
    }

    public static func swapHost(_ url: String, to node: NodeAddress, allowAkamai: Bool = false) -> String? {
        if !allowAkamai && isAkamai(url) { return nil }
        guard var components = URLComponents(string: url) else { return nil }
        components.host = node.host
        // Setting the host alone would keep a peer CDN's non-standard port, such as :4483.
        components.port = node.port
        return components.string
    }

    static func nodes(for mode: NodeMode) -> [NodeAddress] {
        switch mode {
        case .mainland: return mainland.map { NodeAddress(host: $0) }
        case .overseas: return overseas.map { NodeAddress(host: $0) }
        case .custom(let nodes): return nodes
        }
    }

    /// BTR `representationUrls`: the addresses Bilibili gave that suit the mode, then the signed
    /// address swapped onto every node of the mode.
    public static func representationURLs(primary: String, backups: [String], mode: NodeMode, policy: MediaURLPolicy) -> [String] {
        func allowed(_ url: String) -> Bool { URL(string: url).map(policy.allowsURL) ?? false }
        let originals = deduplicated(([primary] + backups).filter(allowed))
        // BTR: a custom mode without servers works like the mainland mode.
        let mode = mode == .custom([]) ? NodeMode.mainland : mode
        let nodes = nodes(for: mode)
        // Some overseas accounts only get akamaized.net addresses; the nodes accept those
        // signatures too, so then every one of them is tried on every node.
        let synthetic: [String]
        if let donor = originals.first(where: { !isAkamai($0) }) {
            synthetic = nodes.compactMap { swapHost(donor, to: $0) }
        } else {
            synthetic = nodes.flatMap { node in originals.compactMap { swapHost($0, to: node, allowAkamai: true) } }
        }
        let allowedOriginals: [String]
        switch mode {
        case .custom(let list):
            let hosts = Set(list.map(\.host))
            allowedOriginals = originals.filter { hosts.contains(host(of: $0)) }
        case .overseas:
            allowedOriginals = originals.filter { !mainland.contains(host(of: $0)) }
        case .mainland:
            allowedOriginals = originals.filter { mainland.contains(host(of: $0)) }
        }
        return deduplicated(allowedOriginals + synthetic.filter(allowed))
    }

    static func deduplicated(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}
