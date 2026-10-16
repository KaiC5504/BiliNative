// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BiliCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "BiliCore", targets: ["BiliShared", "DevLog", "BiliAPI", "DashHLS", "Ripper", "LocalHTTP", "Danmaku"]),
        .executable(name: "ripper-bench", targets: ["ripper-bench"]),
    ],
    targets: [
        .target(name: "BiliShared"),
        .testTarget(name: "BiliSharedTests", dependencies: ["BiliShared"]),
        .target(name: "DevLog", dependencies: ["BiliShared"]),
        .testTarget(name: "DevLogTests", dependencies: ["DevLog", "BiliShared"]),
        .target(name: "Danmaku", dependencies: ["BiliShared"]),
        .testTarget(name: "DanmakuTests", dependencies: ["Danmaku", "BiliShared"]),
        .target(name: "BiliAPI", dependencies: ["BiliShared", "DevLog", "Danmaku"]),
        .testTarget(name: "BiliAPITests", dependencies: ["BiliAPI", "BiliShared", "DevLog", "Danmaku"]),
        .target(name: "DashHLS", dependencies: ["BiliShared"]),
        .testTarget(name: "DashHLSTests", dependencies: ["DashHLS", "BiliShared"]),
        .target(name: "Ripper", dependencies: ["BiliShared", "DevLog"], exclude: ["LICENSE-BTR.txt"]),
        .testTarget(name: "RipperTests", dependencies: ["Ripper", "BiliShared", "DevLog"]),
        .target(name: "LocalHTTP", dependencies: ["BiliShared"]),
        .testTarget(name: "LocalHTTPTests", dependencies: ["LocalHTTP", "BiliShared"]),
        .executableTarget(name: "ripper-bench", dependencies: ["BiliShared", "BiliAPI", "DashHLS", "Ripper", "DevLog"]),
    ],
    swiftLanguageModes: [.v5]
)
