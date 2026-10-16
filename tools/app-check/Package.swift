// swift-tools-version:6.0
// Compile-check only (tools/check-app.sh). The real app is built by XcodeGen from ios/project.yml;
// this manifest mirrors its BiliNative and BiliNativeTests targets. The script copies the sources
// next to it, so the paths are relative to the staging folder, not to this file.
import PackageDescription

let package = Package(
    name: "BiliNativeCheck",
    platforms: [.iOS("26.0")],
    dependencies: [
        .package(path: "BiliCore"),
    ],
    targets: [
        .target(
            name: "BiliNative",
            dependencies: [.product(name: "BiliCore", package: "BiliCore")],
            path: "App",
            swiftSettings: [.define("DEV_TOOLS")]
        ),
        // A plain target, not a test target: the tests are only compiled here, and packaging an
        // .xctest bundle fails on Linux (CopySwiftLibs wants a bitcode strip tool).
        .target(
            name: "BiliNativeTests",
            dependencies: ["BiliNative"],
            path: "AppTests",
            swiftSettings: [.define("DEV_TOOLS")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
