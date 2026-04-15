// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouthType",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MouthType", targets: ["MouthType"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.3"),
    ],
    targets: [
        .executableTarget(
            name: "MouthType",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/MouthType",
            exclude: ["Info.plist", "MouthType.entitlements"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
        .testTarget(
            name: "MouthTypeTests",
            dependencies: ["MouthType"],
            path: "Tests/MouthTypeTests"
        ),
    ]
)
