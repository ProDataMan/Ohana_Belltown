// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OhanaServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
    ]
)
