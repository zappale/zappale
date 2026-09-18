// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "zappale",
    platforms: [
        .macOS(.v15),
        .iOS(.v15),
    ],
    products: [
        .library(name: "ZappaleCore", targets: ["ZappaleCore"]),
    ],
    targets: [
        // 纯逻辑层：零 AppKit/SwiftUI/UIKit 依赖，macOS 与 iOS 共用。
        .target(
            name: "ZappaleCore",
            path: "Sources/ZappaleCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // macOS 应用层：AppKit 服务 + SwiftUI 界面。
        .executableTarget(
            name: "zappale",
            dependencies: ["ZappaleCore"],
            path: "Sources/Zappale",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "zappaleTests",
            dependencies: ["ZappaleCore", "zappale"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
