// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TransformationSwiftUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TransformationSwiftUI",
            targets: ["TransformationSwiftUI"]
        ),
        .executable(
            name: "TransformationSwiftUICLI",
            targets: ["TransformationSwiftUICLI"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-syntax.git",
            from: "509.0.0"
        )
    ],
    targets: [
        .target(
            name: "TransformationSwiftUI",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "TransformationSwiftUICLI",
            dependencies: ["TransformationSwiftUI"]
        ),
        .testTarget(
            name: "TransformationSwiftUITests",
            dependencies: ["TransformationSwiftUI"]
        )
    ]
)
