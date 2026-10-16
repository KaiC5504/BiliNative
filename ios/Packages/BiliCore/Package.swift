// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BiliCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "BiliCore", targets: ["BiliShared", "DevLog", "BiliAPI", "DashHLS"]),
    ],
    targets: [
        .target(name: "BiliShared"),
        .testTarget(name: "BiliSharedTests", dependencies: ["BiliShared"]),
        .target(name: "DevLog", dependencies: ["BiliShared"]),
        .testTarget(name: "DevLogTests", dependencies: ["DevLog", "BiliShared"]),
        .target(name: "BiliAPI", dependencies: ["BiliShared", "DevLog"]),
        .testTarget(name: "BiliAPITests", dependencies: ["BiliAPI", "BiliShared", "DevLog"]),
        .target(name: "DashHLS", dependencies: ["BiliShared"]),
        .testTarget(name: "DashHLSTests", dependencies: ["DashHLS", "BiliShared"]),
    ],
    swiftLanguageModes: [.v5]
)
