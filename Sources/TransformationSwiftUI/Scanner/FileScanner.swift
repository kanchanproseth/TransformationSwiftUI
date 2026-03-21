// SPDX-License-Identifier: MIT
//
// FileScanner.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Scans directories for Swift source files.
//

import Foundation

/// Scans directories for Swift and Interface Builder source files.
public struct FileScanner {

    /// Finds all `.swift` files under the given directory.
    public static func findSwiftFiles(at path: String) -> [URL] {

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: path)

        var files: [URL] = []

        while let file = enumerator?.nextObject() as? String {

            if file.hasSuffix(Strings.swiftSuffix) {

                let url = URL(fileURLWithPath: path)
                    .appendingPathComponent(file)

                files.append(url)

            }

        }

        return files

    }

    /// Finds all `.storyboard` and `.xib` files under the given directory.
    public static func findInterfaceBuilderFiles(at path: String) -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: path)

        var files: [URL] = []

        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(Strings.storyboardSuffix) || file.hasSuffix(Strings.xibSuffix) {
                let url = URL(fileURLWithPath: path)
                    .appendingPathComponent(file)
                files.append(url)
            }
        }

        return files
    }

    /// Finds all Swift and Interface Builder files in a single directory traversal.
    ///
    /// - Returns: A tuple of `(swift: [URL], interfaceBuilder: [URL])`.
    public static func findAllSourceFiles(at path: String) -> (swift: [URL], interfaceBuilder: [URL]) {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: path)

        var swiftFiles: [URL] = []
        var ibFiles: [URL] = []

        while let file = enumerator?.nextObject() as? String {
            let url = URL(fileURLWithPath: path).appendingPathComponent(file)
            if file.hasSuffix(Strings.swiftSuffix) {
                swiftFiles.append(url)
            } else if file.hasSuffix(Strings.storyboardSuffix) || file.hasSuffix(Strings.xibSuffix) {
                ibFiles.append(url)
            }
        }

        return (swift: swiftFiles, interfaceBuilder: ibFiles)
    }

    private enum Strings {
        static let swiftSuffix = ".swift"
        static let storyboardSuffix = ".storyboard"
        static let xibSuffix = ".xib"
    }
}
