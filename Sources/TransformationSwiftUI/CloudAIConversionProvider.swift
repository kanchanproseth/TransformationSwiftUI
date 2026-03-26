// SPDX-License-Identifier: MIT
//
// CloudAIConversionProvider.swift
// Part of the TransformationSwiftUI project
//
// Copyright (c) 2026 Kan Chanproseth and contributors
//
// Description: AI provider that calls cloud-hosted LLM APIs
//              (Anthropic Claude, OpenAI, Perplexity).
//

import Foundation

/// Identifies which cloud API format and service to use.
public enum CloudAPIFormat: String {
    /// Anthropic Claude — uses the Messages API with x-api-key auth.
    case anthropic
    /// OpenAI — uses the Chat Completions API with Bearer auth.
    case openAI
    /// Perplexity — OpenAI-compatible Chat Completions API with Bearer auth.
    case perplexity
}

/// AI provider that calls cloud-hosted LLM APIs.
/// Supports Anthropic (Claude), OpenAI, and Perplexity through a single struct.
public struct CloudAIConversionProvider: AIConversionProvider {

    /// Errors specific to cloud AI calls.
    public enum ProviderError: Error {
        /// The HTTP request failed (non-2xx status code).
        case requestFailed(statusCode: Int)
        /// The HTTP response could not be decoded or had an unexpected shape.
        case invalidResponse
        /// The response contained no usable output.
        case emptyOutput
    }

    // MARK: - Public interface

    /// The human-readable name of the active provider format (used for logging).
    public var formatName: String { format.rawValue }

    // MARK: - Private storage

    private let format: CloudAPIFormat
    private let endpoint: URL
    private let apiKey: String
    private let model: String
    private let debugEnabled: Bool
    private let session: URLSession
    private let timeout: TimeInterval

    // MARK: - Init

    public init(
        format: CloudAPIFormat,
        endpoint: URL,
        apiKey: String,
        model: String,
        debugEnabled: Bool = false,
        session: URLSession = .shared,
        timeout: TimeInterval = 120
    ) {
        self.format = format
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.debugEnabled = debugEnabled
        self.session = session
        self.timeout = timeout
    }

    // MARK: - fromEnvironment

    /// Attempts to build a provider from process environment variables.
    /// Detection order: Anthropic → OpenAI → Perplexity. First API key found wins.
    /// Returns `nil` when no cloud API key is set.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CloudAIConversionProvider? {
        let debug = (environment[Strings.aiDebugKey] ?? Strings.boolFalseStr) == Strings.boolTrueStr

        // Anthropic (Claude)
        if let key = environment[Strings.anthropicAPIKeyEnv], !key.isEmpty {
            let url = environment[Strings.anthropicEndpointEnv].flatMap { URL(string: $0) }
                ?? URL(string: Strings.anthropicDefaultEndpoint)!
            let mdl = environment[Strings.anthropicModelEnv] ?? Strings.anthropicDefaultModel
            return CloudAIConversionProvider(format: .anthropic, endpoint: url, apiKey: key,
                                             model: mdl, debugEnabled: debug)
        }

        // OpenAI
        if let key = environment[Strings.openAIAPIKeyEnv], !key.isEmpty {
            let url = environment[Strings.openAIEndpointEnv].flatMap { URL(string: $0) }
                ?? URL(string: Strings.openAIDefaultEndpoint)!
            let mdl = environment[Strings.openAIModelEnv] ?? Strings.openAIDefaultModel
            return CloudAIConversionProvider(format: .openAI, endpoint: url, apiKey: key,
                                             model: mdl, debugEnabled: debug)
        }

        // Perplexity
        if let key = environment[Strings.perplexityAPIKeyEnv], !key.isEmpty {
            let url = environment[Strings.perplexityEndpointEnv].flatMap { URL(string: $0) }
                ?? URL(string: Strings.perplexityDefaultEndpoint)!
            let mdl = environment[Strings.perplexityModelEnv] ?? Strings.perplexityDefaultModel
            return CloudAIConversionProvider(format: .perplexity, endpoint: url, apiKey: key,
                                             model: mdl, debugEnabled: debug)
        }

        return nil
    }

    // MARK: - AIConversionProvider

    public func convert(_ request: AIConversionRequest) throws -> String? {
        let systemPrompt = AIPromptBuilder.systemPrompt
        let userPrompt = AIPromptBuilder.buildUserPrompt(from: request)

        let (body, headers) = try buildRequestPayload(systemPrompt: systemPrompt, userPrompt: userPrompt)

        var urlRequest = URLRequest(url: endpoint, timeoutInterval: timeout)
        urlRequest.httpMethod = Strings.httpPost
        urlRequest.httpBody = body
        for (field, value) in headers {
            urlRequest.addValue(value, forHTTPHeaderField: field)
        }

        if debugEnabled {
            log(Strings.logPostPrefix + endpoint.absoluteString)
            log(Strings.logFormatPrefix + format.rawValue + Strings.logModelInfix + model)
            if let s = String(data: body, encoding: .utf8) { log(Strings.logPayloadPrefix + s) }
        }

        let (responseData, response) = try send(request: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            if debugEnabled { log(Strings.logInvalidResponse) }
            throw ProviderError.invalidResponse
        }
        if debugEnabled {
            let body = String(data: responseData, encoding: .utf8) ?? Strings.nonUtf8
            log(Strings.logStatusPrefix + String(http.statusCode))
            log(Strings.logBodyPrefix + body)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.requestFailed(statusCode: http.statusCode)
        }

        let output = try extractContent(from: responseData)
        guard let output, !output.isEmpty else { throw ProviderError.emptyOutput }
        return output
    }

    // MARK: - Request Building

    private func buildRequestPayload(
        systemPrompt: String,
        userPrompt: String
    ) throws -> (Data, [(String, String)]) {
        switch format {
        case .anthropic:
            return try buildAnthropicPayload(systemPrompt: systemPrompt, userPrompt: userPrompt)
        case .openAI, .perplexity:
            return try buildOpenAIPayload(systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }

    private func buildAnthropicPayload(
        systemPrompt: String,
        userPrompt: String
    ) throws -> (Data, [(String, String)]) {
        let payload: [String: Any] = [
            Strings.jsonModel: model,
            Strings.jsonMaxTokens: 4096,
            Strings.jsonSystem: systemPrompt,
            Strings.jsonMessages: [
                [Strings.jsonRole: Strings.roleUser, Strings.jsonContent: userPrompt]
            ],
            Strings.jsonTemperature: 0.2,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let headers: [(String, String)] = [
            (Strings.contentTypeHeader, Strings.contentTypeJson),
            (Strings.anthropicKeyHeader, apiKey),
            (Strings.anthropicVersionHeader, Strings.anthropicVersionValue),
        ]
        return (data, headers)
    }

    private func buildOpenAIPayload(
        systemPrompt: String,
        userPrompt: String
    ) throws -> (Data, [(String, String)]) {
        let payload: [String: Any] = [
            Strings.jsonModel: model,
            Strings.jsonMessages: [
                [Strings.jsonRole: Strings.roleSystem, Strings.jsonContent: systemPrompt],
                [Strings.jsonRole: Strings.roleUser, Strings.jsonContent: userPrompt],
            ],
            Strings.jsonTemperature: 0.2,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let headers: [(String, String)] = [
            (Strings.contentTypeHeader, Strings.contentTypeJson),
            (Strings.authorizationHeader, Strings.bearerPrefix + apiKey),
        ]
        return (data, headers)
    }

    // MARK: - Response Parsing

    private func extractContent(from data: Data) throws -> String? {
        switch format {
        case .anthropic:
            return try extractAnthropicContent(from: data)
        case .openAI, .perplexity:
            return try extractOpenAIContent(from: data)
        }
    }

    private func extractAnthropicContent(from data: Data) throws -> String? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json[Strings.jsonContent] as? [[String: Any]],
              let first = content.first,
              let text = first[Strings.jsonText] as? String else {
            throw ProviderError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractOpenAIContent(from data: Data) throws -> String? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json[Strings.jsonChoices] as? [[String: Any]],
              let first = choices.first,
              let message = first[Strings.jsonMessage] as? [String: Any],
              let content = message[Strings.jsonContent] as? String else {
            throw ProviderError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTTP

    private func send(request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error> = .failure(ProviderError.invalidResponse)

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
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    private func log(_ message: String) {
        let line = message + Strings.newline
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    // MARK: - String constants

    private enum Strings {
        // Environment variable keys
        static let anthropicAPIKeyEnv       = "TRANSFORMATION_SWIFTUI_ANTHROPIC_API_KEY"
        static let anthropicEndpointEnv     = "TRANSFORMATION_SWIFTUI_ANTHROPIC_ENDPOINT"
        static let anthropicModelEnv        = "TRANSFORMATION_SWIFTUI_ANTHROPIC_MODEL"

        static let openAIAPIKeyEnv          = "TRANSFORMATION_SWIFTUI_OPENAI_API_KEY"
        static let openAIEndpointEnv        = "TRANSFORMATION_SWIFTUI_OPENAI_ENDPOINT"
        static let openAIModelEnv           = "TRANSFORMATION_SWIFTUI_OPENAI_MODEL"

        static let perplexityAPIKeyEnv      = "TRANSFORMATION_SWIFTUI_PERPLEXITY_API_KEY"
        static let perplexityEndpointEnv    = "TRANSFORMATION_SWIFTUI_PERPLEXITY_ENDPOINT"
        static let perplexityModelEnv       = "TRANSFORMATION_SWIFTUI_PERPLEXITY_MODEL"

        static let aiDebugKey               = "TRANSFORMATION_SWIFTUI_AI_DEBUG"

        // Default endpoints
        static let anthropicDefaultEndpoint  = "https://api.anthropic.com/v1/messages"
        static let openAIDefaultEndpoint     = "https://api.openai.com/v1/chat/completions"
        static let perplexityDefaultEndpoint = "https://api.perplexity.ai/chat/completions"

        // Default models
        static let anthropicDefaultModel  = "claude-sonnet-4-20250514"
        static let openAIDefaultModel     = "gpt-4o"
        static let perplexityDefaultModel = "sonar"

        // HTTP
        static let httpPost              = "POST"
        static let contentTypeHeader     = "Content-Type"
        static let contentTypeJson       = "application/json"
        static let authorizationHeader   = "Authorization"
        static let bearerPrefix          = "Bearer "
        static let anthropicKeyHeader    = "x-api-key"
        static let anthropicVersionHeader = "anthropic-version"
        static let anthropicVersionValue  = "2023-06-01"

        // JSON keys — Anthropic
        static let jsonModel        = "model"
        static let jsonMaxTokens    = "max_tokens"
        static let jsonSystem       = "system"
        static let jsonMessages     = "messages"
        static let jsonTemperature  = "temperature"
        static let jsonRole         = "role"
        static let jsonContent      = "content"
        static let jsonText         = "text"
        // JSON keys — OpenAI
        static let jsonChoices      = "choices"
        static let jsonMessage      = "message"

        static let roleSystem = "system"
        static let roleUser   = "user"

        // Logging
        static let logPostPrefix      = "[CloudAI] POST "
        static let logFormatPrefix    = "[CloudAI] Format: "
        static let logModelInfix      = " model: "
        static let logPayloadPrefix   = "[CloudAI] Payload: "
        static let logInvalidResponse = "[CloudAI] Invalid HTTP response."
        static let logStatusPrefix    = "[CloudAI] Status: "
        static let logBodyPrefix      = "[CloudAI] Body: "

        static let nonUtf8       = "<non-utf8>"
        static let newline       = "\n"
        static let boolTrueStr   = "1"
        static let boolFalseStr  = "0"
    }
}
