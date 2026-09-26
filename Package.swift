// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Booklet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Booklet", targets: ["Booklet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "BookletCore"),
        .executableTarget(
            name: "Booklet",
            dependencies: ["BookletCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "BookletCoreTests",
            dependencies: ["BookletCore"]
        ),
    ]
)
