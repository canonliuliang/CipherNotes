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
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("Security"),
                .linkedFramework("PDFKit")
            ]
        ),
        .testTarget(name: "CipherNotesTests", dependencies: ["CipherNotes"])
    ]
)
