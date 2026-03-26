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
        ),
        .package(
            url: "https://github.com/realm/SwiftLint.git",
            "0.58.0"..<"0.59.0"
        )
    ],
    targets: [
        .target(
            name: "TransformationSwiftUI",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        ),
        .executableTarget(
            name: "TransformationSwiftUICLI",
            dependencies: ["TransformationSwiftUI"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        ),
        .testTarget(
            name: "TransformationSwiftUITests",
            dependencies: ["TransformationSwiftUI"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        )
    ]
)
