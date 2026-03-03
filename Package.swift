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
        .executable(name: "pdf-ingest", targets: ["PDFIngest"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "5.0.0"),
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
            name: "PDFIngest",
            dependencies: [
                "Ingest",
                "Store",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/PDFIngest"
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
