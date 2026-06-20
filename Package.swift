// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PokeConnect",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Poke Connect",
            targets: ["PokeConnect"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PokeConnect",
            path: "Sources/PokeConnect",
            resources: [
                .copy("Resources/mac-local-manager")
            ]
        )
    ]
)
