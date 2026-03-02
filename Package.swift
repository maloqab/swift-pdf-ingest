// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPDFIngestRuntime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Ingest", targets: ["Ingest"]),
        .library(name: "Store", targets: ["Store"]),
        .executable(name: "SwiftIngestRuntime", targets: ["SwiftIngestRuntime"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "Ingest",
            path: "Sources/Ingest"
        ),
        .target(
            name: "Store",
            dependencies: ["Ingest"],
            path: "Sources/Store"
        ),
        .executableTarget(
            name: "SwiftIngestRuntime",
            dependencies: ["Ingest", "Store"],
            path: "Sources/SwiftIngestRuntime"
        ),
        .testTarget(
            name: "IngestTests",
            dependencies: [
                "Ingest",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/IngestTests"
        ),
        .testTarget(
            name: "StoreTests",
            dependencies: [
                "Store",
                "Ingest",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/StoreTests"
        )
    ]
)
