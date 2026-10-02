// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RivoDocumentEngine",
    platforms: [.iOS("26.2"), .macOS(.v15)],
    products: [.library(name: "RivoDocumentEngine", targets: ["RivoDocumentEngine"])],
    targets: [
        // Always present: the manifest runs on the host, whereas compression
        // is compiled for the target. macOS -> Android must still expose zlib.
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.brew(["zlib"]), .apt(["zlib1g-dev"])]),
        .target(
            name: "RivoZIPFoundation", dependencies: ["CZlib"], path: "Vendor/ZIPFoundation/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "RivoDocumentEngine", dependencies: ["RivoZIPFoundation", "CZlib"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "RivoDocumentEngineTests", dependencies: ["RivoDocumentEngine", "RivoZIPFoundation"],
            resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
