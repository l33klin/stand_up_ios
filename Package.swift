// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StandUpCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "StandUpCore", targets: ["StandUpCore"])],
    targets: [
        .target(name: "StandUpCore", path: "ios/StandUp/Core"),
        .testTarget(name: "StandUpCoreTests", dependencies: ["StandUpCore"], path: "tests/StandUpCoreTests"),
        .target(name: "StandUpModel", dependencies: ["StandUpCore"], path: "ios/StandUp",
                exclude: ["Core", "Views", "StandUpApp.swift", "Info.plist", "Assets.xcassets"]),
        .testTarget(name: "StandUpModelTests", dependencies: ["StandUpModel", "StandUpCore"], path: "tests/StandUpModelTests")
    ]
)
