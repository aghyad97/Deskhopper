// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Deskhopper",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Deskhopper",
            path: "Sources/Deskhopper",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Deskhopper/Resources/Info.plist"
                ])
            ]
        )
    ]
)
