// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CipherNotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CipherNotes", targets: ["CipherNotes"])
    ],
    targets: [
        .executableTarget(
            name: "CipherNotes",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication")
            ]
        ),
        .testTarget(name: "CipherNotesTests", dependencies: ["CipherNotes"])
    ]
)
