// SPDX-License-Identifier: MIT
//
// LocalAIConversionProvider.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: AI provider that calls a locally hosted HTTP service.
//

import Foundation

/// AI provider that calls a locally hosted HTTP service.
public struct LocalAIConversionProvider: AIConversionProvider {
    /// Errors that can occur while calling the local AI service.
    public enum ProviderError: Error {
        /// The endpoint URL is missing or malformed.
        case invalidEndpoint
        /// The HTTP request failed or returned a non-2xx status.
        case requestFailed
        /// The HTTP response could not be decoded.
        case invalidResponse
        /// The response contained no usable output.
        case emptyOutput
    }

    private let endpoint: URL
    private let model: String
    private let debugEnabled: Bool
    private let session: URLSession
    private let timeout: TimeInterval

    /// Creates a provider that targets a local HTTP endpoint.
    public init(
        endpoint: URL,
        model: String? = nil,
        debugEnabled: Bool = false,
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.model = model ?? Strings.defaultModel
        self.debugEnabled = debugEnabled
        self.session = session
        self.timeout = timeout
    }

    /// Builds a provider from environment variables, or returns nil when missing.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocalAIConversionProvider? {
        guard let raw = environment[Strings.aiEndpointKey],
              let url = URL(string: raw) else {
            return nil
        }
        let model = environment[Strings.aiModelKey]
        let debugEnabled = (environment[Strings.aiDebugKey] ?? Strings.boolFalseInt) == Strings.boolTrueInt
        return LocalAIConversionProvider(endpoint: url, model: model, debugEnabled: debugEnabled)
    }

    /// Sends the request to the local AI service and returns SwiftUI output.
    public func convert(_ request: AIConversionRequest) throws -> String? {
        let payload = LocalAIRequestPayload(model: model, prompt: buildPrompt(from: request))
        let data = try JSONEncoder().encode(payload)

        var urlRequest = URLRequest(url: endpoint, timeoutInterval: timeout)
        urlRequest.httpMethod = Strings.httpPost
        urlRequest.addValue(Strings.contentTypeJson, forHTTPHeaderField: Strings.contentTypeHeader)
        urlRequest.httpBody = data

        if debugEnabled {
            let payloadString = String(data: data, encoding: .utf8) ?? Strings.nonUtf8
            log(Strings.logPostPrefix + endpoint.absoluteString)
            log(Strings.logPayloadPrefix + payloadString)
        }

        let (responseData, response) = try send(request: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            if debugEnabled {
                log(Strings.logInvalidResponse)
            }
            throw ProviderError.invalidResponse
        }
        if debugEnabled {
            let body = String(data: responseData, encoding: .utf8) ?? Strings.nonUtf8
            log(Strings.logStatusPrefix + String(httpResponse.statusCode))
            log(Strings.logBodyPrefix + body)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.requestFailed
        }

        let decoded = try JSONDecoder().decode(LocalAIResponsePayload.self, from: responseData)
        let output = (decoded.swiftui ?? decoded.response)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let output, !output.isEmpty {
            return output
        }
        throw ProviderError.emptyOutput
    }

    private func buildPrompt(from request: AIConversionRequest) -> String {
        let rootNames = request.controller.rootElements.map { $0.name }.joined(separator: Strings.commaSpace)
        let hintText = request.layoutHints.joined(separator: Strings.newline)
        let patternText = request.patterns.map { $0.type.displayName + Strings.patternSeparator + $0.elements.joined(separator: Strings.commaSpace) }.joined(separator: Strings.newline)
        let contextText = formatContext(request.contextChunks)

        return """
        Convert this UIKit view controller to SwiftUI.
        Controller: \(request.controller.name)
        Root elements: \(rootNames)
        Complexity score: \(request.complexityScore)
        Layout patterns:
        \(patternText)
        Layout hints:
        \(hintText)
        Related code snippets:
        \(contextText)
        """
    }

    private func formatContext(_ chunks: [CodeChunk]) -> String {
        guard !chunks.isEmpty else { return Strings.noneText }
        let maxChunks = 3
        let maxCharacters = 400
        let entries = chunks.prefix(maxChunks).map { chunk -> String in
            let trimmed = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet: String
            if trimmed.count > maxCharacters {
                snippet = String(trimmed.prefix(maxCharacters)) + Strings.ellipsis
            } else {
                snippet = trimmed
            }
            return Strings.contextPrefix + chunk.filePath + Strings.contextLineSeparator + String(chunk.startLine) + Strings.contextRangeSeparator + String(chunk.endLine) + Strings.contextSuffix + Strings.newline + snippet
        }
        return entries.joined(separator: Strings.contextEntrySeparator)
    }

    private func send(request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error> = .failure(ProviderError.requestFailed)

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(ProviderError.invalidResponse)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private func log(_ message: String) {
        let line = message + Strings.newline
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private enum Strings {
        static let aiEndpointKey = "TRANSFORMATION_SWIFTUI_AI_ENDPOINT"
        static let aiModelKey = "TRANSFORMATION_SWIFTUI_AI_MODEL"
        static let aiDebugKey = "TRANSFORMATION_SWIFTUI_AI_DEBUG"
        static let defaultModel = "deepseek-r1:1.5b"

        static let httpPost = "POST"
        static let contentTypeHeader = "Content-Type"
        static let contentTypeJson = "application/json"

        static let logPostPrefix = "[AI] POST "
        static let logPayloadPrefix = "[AI] Payload: "
        static let logInvalidResponse = "[AI] Invalid HTTP response."
        static let logStatusPrefix = "[AI] Status: "
        static let logBodyPrefix = "[AI] Body: "

        static let nonUtf8 = "<non-utf8>"
        static let noneText = "None"
        static let ellipsis = "..."
        static let newline = "\n"
        static let commaSpace = ", "
        static let patternSeparator = ": "

        static let contextPrefix = "["
        static let contextLineSeparator = ":"
        static let contextRangeSeparator = "-"
        static let contextSuffix = "]"
        static let contextEntrySeparator = "\n---\n"

        static let boolTrueInt = "1"
        static let boolFalseInt = "0"
    }
}

private struct LocalAIRequestPayload: Encodable {
    let model: String
    let prompt: String
}

private struct LocalAIResponsePayload: Decodable {
    let swiftui: String?
    let response: String?
}
