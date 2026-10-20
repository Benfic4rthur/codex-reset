// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexReset",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexReset", targets: ["CodexReset"]),
        .executable(name: "CodexResetCompanion", targets: ["CodexResetCompanion"])
    ],
    targets: [
        .executableTarget(
            name: "CodexReset",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "CodexResetCompanion"),
        .testTarget(name: "CodexResetTests", dependencies: ["CodexReset"])
    ]
)
