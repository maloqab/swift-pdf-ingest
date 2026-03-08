// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-pdf-ingest",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Ingest", targets: ["Ingest"]),
        .library(name: "Store", targets: ["Store"]),
        .library(name: "IngestRuntime", targets: ["IngestRuntime"]),
        .executable(name: "pdf-ingest", targets: ["PDFIngest"]),
        .executable(name: "pdf-ingest-web", targets: ["PDFIngestWeb"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "5.0.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.111.0"),
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
        .target(
            name: "IngestRuntime",
            dependencies: [
                "Ingest",
                "Store",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/IngestRuntime"
        ),
        .executableTarget(
            name: "PDFIngest",
            dependencies: [
                "IngestRuntime",
            ],
            path: "Sources/PDFIngest",
            sources: ["main.swift"]
        ),
        .executableTarget(
            name: "PDFIngestWeb",
            dependencies: [
                "Ingest",
                "IngestRuntime",
                "Store",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/PDFIngestWeb",
            resources: [
                .process("Public")
            ]
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
        ),
        .testTarget(
            name: "PDFIngestTests",
            dependencies: [
                "IngestRuntime",
                "Ingest",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/PDFIngestTests"
        )
    ]
)
