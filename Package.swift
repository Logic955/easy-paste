// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EasyPaste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EasyPaste", targets: ["EasyPaste"])
    ],
    targets: [
        .target(
            name: "EasyPasteCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "EasyPaste",
            dependencies: ["EasyPasteCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(name: "EasyPasteCoreTests", dependencies: ["EasyPasteCore"])
    ]
)
