// SPDX-License-Identifier: MIT
//
// RAGIndex.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: Builds and queries a retrieval index for code context.
//

import Foundation

/// A chunk of source code used for retrieval.
public struct CodeChunk: Hashable {
    /// A stable identifier for this chunk (file path plus line range).
    public let id: String

    /// The file path the chunk came from.
    public let filePath: String

    /// The 1-based start line of the chunk in the source file.
    public let startLine: Int

    /// The 1-based end line of the chunk in the source file.
    public let endLine: Int

    /// The raw text content of the chunk.
    public let text: String

    public init(id: String, filePath: String, startLine: Int, endLine: Int, text: String) {
        self.id = id
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.text = text
    }
}

/// Configuration for retrieval-augmented generation indexing.
public struct RAGConfig: Equatable {
    /// Enables or disables RAG indexing and retrieval.
    public let enabled: Bool

    /// Number of top results to return for a query.
    public let topK: Int

    /// Max characters per chunk when splitting source files.
    public let chunkSize: Int

    /// Overlap size in characters between consecutive chunks.
    public let chunkOverlap: Int

    public init(enabled: Bool, topK: Int, chunkSize: Int, chunkOverlap: Int) {
        self.enabled = enabled
        self.topK = topK
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
    }

    /// Default configuration used when environment variables are not provided.
    public static let `default` = RAGConfig(enabled: false, topK: 4, chunkSize: 1200, chunkOverlap: 200)

    /// Builds a config from process environment variables.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RAGConfig {
        let enabled = parseBool(environment[Strings.ragEnabledKey]) ?? false
        let topK = Int(environment[Strings.ragTopKKey] ?? Strings.empty) ?? RAGConfig.default.topK
        let chunkSize = Int(environment[Strings.ragChunkSizeKey] ?? Strings.empty) ?? RAGConfig.default.chunkSize
        let chunkOverlap = Int(environment[Strings.ragChunkOverlapKey] ?? Strings.empty) ?? RAGConfig.default.chunkOverlap
        return RAGConfig(enabled: enabled, topK: max(1, topK), chunkSize: max(200, chunkSize), chunkOverlap: max(0, chunkOverlap))
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case Strings.boolTrueInt, Strings.boolTrue, Strings.boolYes, Strings.boolOn:
            return true
        case Strings.boolFalseInt, Strings.boolFalse, Strings.boolNo, Strings.boolOff:
            return false
        default:
            return nil
        }
    }

    private enum Strings {
        static let empty = ""
        static let ragEnabledKey = "TRANSFORMATION_SWIFTUI_RAG_ENABLED"
        static let ragTopKKey = "TRANSFORMATION_SWIFTUI_RAG_TOP_K"
        static let ragChunkSizeKey = "TRANSFORMATION_SWIFTUI_RAG_CHUNK_SIZE"
        static let ragChunkOverlapKey = "TRANSFORMATION_SWIFTUI_RAG_CHUNK_OVERLAP"

        static let boolTrueInt = "1"
        static let boolTrue = "true"
        static let boolYes = "yes"
        static let boolOn = "on"
        static let boolFalseInt = "0"
        static let boolFalse = "false"
        static let boolNo = "no"
        static let boolOff = "off"
    }
}

/// Converts raw text into embedding vectors.
public protocol EmbeddingProvider {
    /// Returns a vector representation for the given text.
    func embed(_ text: String) -> [Double]
}

/// A lightweight embedding provider that hashes tokens into a fixed-size vector.
public final class HashingEmbeddingProvider: EmbeddingProvider {
    private let dimensions: Int

    /// Creates a hashing embedder with the desired vector size.
    public init(dimensions: Int = 64) {
        self.dimensions = max(8, dimensions)
    }

    /// Embeds text by hashing tokens into the vector space.
    public func embed(_ text: String) -> [Double] {
        var vector = Array(repeating: 0.0, count: dimensions)
        let tokens = tokenize(text)
        for token in tokens {
            let index = abs(hash(token)) % dimensions
            vector[index] += 1
        }
        return normalize(vector)
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private func hash(_ token: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        let prime: UInt64 = 1099511628211
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return Int(truncatingIfNeeded: hash)
    }

    private func normalize(_ vector: [Double]) -> [Double] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

/// Storage abstraction for embedding vectors and their associated chunks.
public protocol VectorStore {
    /// Adds embedded chunks to the store.
    func add(chunks: [CodeChunk], embeddings: [[Double]])

    /// Queries the store and returns the top-K chunks with similarity scores.
    func query(vector: [Double], topK: Int) -> [(CodeChunk, Double)]
}

/// An in-memory vector store for small to medium projects.
public final class InMemoryVectorStore: VectorStore {
    /// Creates an empty in-memory store.
    public init() {}

    private var chunks: [CodeChunk] = []
    private var embeddings: [[Double]] = []

    /// Adds chunks and embeddings to the in-memory store.
    public func add(chunks: [CodeChunk], embeddings: [[Double]]) {
        guard chunks.count == embeddings.count else { return }
        self.chunks.append(contentsOf: chunks)
        self.embeddings.append(contentsOf: embeddings)
    }

    /// Returns the top-K most similar chunks for the provided vector.
    public func query(vector: [Double], topK: Int) -> [(CodeChunk, Double)] {
        guard !vector.isEmpty else { return [] }
        var scored: [(CodeChunk, Double)] = []
        scored.reserveCapacity(chunks.count)
        for (index, chunk) in chunks.enumerated() {
            let score = cosineSimilarity(vector, embeddings[index])
            scored.append((chunk, score))
        }
        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(max(1, topK))).filter { $0.1 > 0 }
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let denom = sqrt(magA) * sqrt(magB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}

/// Splits source text into overlapping chunks for retrieval.
public final class CodeChunker {
    private let chunkSize: Int
    private let overlap: Int

    /// Creates a chunker configured with size and overlap in characters.
    public init(chunkSize: Int, overlap: Int) {
        self.chunkSize = max(200, chunkSize)
        self.overlap = max(0, overlap)
    }

    /// Splits a file into CodeChunk entries.
    public func chunk(text: String, filePath: String) -> [CodeChunk] {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        var chunks: [CodeChunk] = []
        var currentLines: [String] = []
        var currentCount = 0
        var startLine = 1

        func flush(endLine: Int) {
            let content = currentLines.joined(separator: Strings.newline)
            let id = filePath + Strings.chunkIdSeparator + String(startLine) + Strings.chunkRangeSeparator + String(endLine)
            let chunk = CodeChunk(id: id, filePath: filePath, startLine: startLine, endLine: endLine, text: content)
            chunks.append(chunk)
        }

        for (index, line) in lines.enumerated() {
            let lineLength = line.count + 1
            if !currentLines.isEmpty, currentCount + lineLength > chunkSize {
                flush(endLine: index)
                if overlap > 0 {
                    let overlapped = overlapLines(from: currentLines)
                    currentLines = overlapped
                    currentCount = currentLines.reduce(0) { $0 + $1.count + 1 }
                    startLine = index - currentLines.count + 1
                } else {
                    currentLines = []
                    currentCount = 0
                    startLine = index + 1
                }
            }
            currentLines.append(line)
            currentCount += lineLength
        }

        if !currentLines.isEmpty {
            flush(endLine: lines.count)
        }

        return chunks
    }

    private func overlapLines(from lines: [String]) -> [String] {
        guard overlap > 0 else { return [] }
        var selected: [String] = []
        var count = 0
        for line in lines.reversed() {
            selected.append(line)
            count += line.count + 1
            if count >= overlap {
                break
            }
        }
        return selected.reversed()
    }

    private enum Strings {
        static let newline = "\n"
        static let chunkIdSeparator = "#L"
        static let chunkRangeSeparator = "-"
    }
}

/// End-to-end retrieval index for project source files.
public final class RAGIndex {
    private let embedder: EmbeddingProvider
    private let store: VectorStore
    private let chunker: CodeChunker

    /// Creates a RAG index with a configuration, embedder, and vector store.
    public init(
        config: RAGConfig,
        embedder: EmbeddingProvider = HashingEmbeddingProvider(),
        store: VectorStore = InMemoryVectorStore()
    ) {
        self.embedder = embedder
        self.store = store
        self.chunker = CodeChunker(chunkSize: config.chunkSize, overlap: config.chunkOverlap)
    }

    /// Indexes the given files and returns the number of chunks stored.
    public func indexFiles(_ files: [URL]) -> Int {
        var allChunks: [CodeChunk] = []
        var allEmbeddings: [[Double]] = []

        for file in files {
            guard let text = try? String(contentsOf: file) else { continue }
            let chunks = chunker.chunk(text: text, filePath: file.path)
            let embeddings = chunks.map { embedder.embed($0.text) }
            allChunks.append(contentsOf: chunks)
            allEmbeddings.append(contentsOf: embeddings)
        }

        store.add(chunks: allChunks, embeddings: allEmbeddings)
        return allChunks.count
    }

    /// Retrieves the top-K most relevant chunks for a query string.
    public func retrieve(query: String, topK: Int) -> [CodeChunk] {
        let vector = embedder.embed(query)
        return store.query(vector: vector, topK: topK).map { $0.0 }
    }
}

/// Builds a retrieval query string from a view controller model.
public struct RAGQueryBuilder {
    /// Produces a query string based on element names, types, and constraint items.
    public static func build(for controller: ViewControllerModel) -> String {
        let nodes = collectNodes(from: controller.rootElements)
        let nodeNames = nodes.map { $0.name }
        let typeNames = nodes.compactMap { $0.type?.typeName }
        let constraintItems = controller.constraints.flatMap { constraint -> [String] in
            var items = [constraint.firstItem]
            if let second = constraint.secondItem {
                items.append(second)
            }
            return items
        }

        let tokens = ([controller.name] + nodeNames + typeNames + constraintItems)
        return tokens.joined(separator: Strings.space)
    }

    private static func collectNodes(from roots: [UIElementNode]) -> [UIElementNode] {
        var result: [UIElementNode] = []
        for node in roots {
            result.append(node)
            result.append(contentsOf: collectNodes(from: node.children))
        }
        return result
    }

    private enum Strings {
        static let space = " "
    }
}
