// swift-tools-version: 5.10
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
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "600.0.0"
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
