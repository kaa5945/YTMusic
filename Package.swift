// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YTMusic",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "YTMusicCore",
            path: "Sources",
            exclude: [
                "App/main.swift",
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "YTMusic",
            dependencies: ["YTMusicCore"],
            path: "Sources/App",
            exclude: ["AppDelegate.swift"],
            sources: ["main.swift"],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "SmokeTests",
            dependencies: ["YTMusicCore"],
            path: "SmokeTests",
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        )
    ]
)
