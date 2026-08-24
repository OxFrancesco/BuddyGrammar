// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BuddyGrammarKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "BuddyGrammarKit", targets: ["BuddyGrammarKit"]),
    ],
    targets: [
        .target(
            name: "BuddyGrammarKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BuddyGrammarKitTests",
            dependencies: ["BuddyGrammarKit"],
            resources: [.copy("Fixtures/KeyboardContract")]
        ),
    ]
)
