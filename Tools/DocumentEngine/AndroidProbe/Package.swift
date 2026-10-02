// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RivoEngineProbe",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../Packages/RivoDocumentEngine")],
    targets: [
        .executableTarget(
            name: "RivoEngineProbe",
            dependencies: [
                .product(name: "RivoDocumentEngine", package: "RivoDocumentEngine")
            ])
    ],
    swiftLanguageModes: [.v5]
)
