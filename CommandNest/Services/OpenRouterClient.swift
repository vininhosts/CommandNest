import Foundation

protocol OpenRouterServicing {
    func fetchModelIDs() async throws -> [String]
    func streamChat(apiKey: String, model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
    func completeChat(apiKey: String, model: String, messages: [ChatMessage]) async throws -> String
    func completeChatWithTools(apiKey: String, model: String, messages: [OpenRouterChatMessagePayload], tools: [OpenRouterTool]) async throws -> OpenRouterChatResult
}

protocol OpenRouterURLSession {
    func bytes(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (URLSession.AsyncBytes, URLResponse)
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
}

extension URLSession: OpenRouterURLSession {}

enum OpenRouterClientError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidAPIKey(String?)
    case rateLimited(String?)
    case modelError(String?)
    case serverError(Int, String?)
    case networkFailure(String)
    case invalidResponse
    case decodingFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenRouter API key in Settings before sending a prompt."
        case .invalidEndpoint:
            return "The OpenRouter endpoint URL is invalid."
        case .invalidAPIKey(let message):
            return message ?? "OpenRouter rejected the API key. Check it in Settings."
        case .rateLimited(let message):
            return message ?? "OpenRouter rate limited the request. Try again shortly."
        case .modelError(let message):
            return message ?? "OpenRouter could not use the selected model. Choose another model in Settings."
        case .serverError(let status, let message):
            if let message, !message.isEmpty {
                return "OpenRouter returned HTTP \(status): \(message)"
            }
            return "OpenRouter returned HTTP \(status)."
        case .networkFailure(let message):
            return "Network failure: \(message)"
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .decodingFailed(let message):
            return "Could not decode OpenRouter response: \(message)"
        case .emptyResponse:
            return "OpenRouter returned an empty response."
        }
    }
}

final class OpenRouterClient: OpenRouterServicing {
    private let endpointString: String
    private let modelsEndpointString: String
    private let session: OpenRouterURLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        endpointString: String = Constants.openRouterEndpoint,
        modelsEndpointString: String = Constants.openRouterModelsEndpoint,
        session: OpenRouterURLSession = URLSession.shared
    ) {
        self.endpointString = endpointString
        self.modelsEndpointString = modelsEndpointString
        self.session = session
    }

    func fetchModelIDs() async throws -> [String] {
        guard let endpoint = URL(string: modelsEndpointString) else {
            throw OpenRouterClientError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(Constants.openRouterReferer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(Constants.openRouterTitle, forHTTPHeaderField: "X-Title")

        do {
            let (data, response) = try await session.data(for: request, delegate: nil)
            try validateDataResponse(response, data: data)

            let modelResponse = try decoder.decode(ModelsResponse.self, from: data)
            var seen = Set<String>()
            let ids = ([Constants.freeRouterModelID] + modelResponse.data.map(\.id))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { seen.insert($0).inserted }

            return ids.isEmpty ? Constants.defaultModelIDs : ids
        } catch let error as OpenRouterClientError {
            throw error
        } catch let error as URLError {
            throw OpenRouterClientError.networkFailure(error.localizedDescription)
        } catch {
            throw OpenRouterClientError.decodingFailed(error.localizedDescription)
        }
    }

    func streamChat(apiKey: String, model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(apiKey: apiKey, model: model, messages: messages, stream: true)
                    let (bytes, response) = try await session.bytes(for: request, delegate: nil)

                    try await validateStreamingResponse(response, bytes: bytes)

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let payload = Self.payload(fromServerSentEventLine: line) else {
                            continue
                        }

                        if payload == "[DONE]" {
                            break
                        }

                        let data = Data(payload.utf8)
                        do {
                            let event = try decoder.decode(StreamResponse.self, from: data)
                            if let error = event.error {
                                throw mapAPIError(statusCode: 200, message: error.message)
                            }

                            for choice in event.choices ?? [] {
                                if let content = choice.delta.content, !content.isEmpty {
                                    continuation.yield(content)
                                }
                            }
                        } catch let error as OpenRouterClientError {
                            throw error
                        } catch {
                            throw OpenRouterClientError.decodingFailed(error.localizedDescription)
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as OpenRouterClientError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: OpenRouterClientError.networkFailure(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: OpenRouterClientError.networkFailure(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func completeChat(apiKey: String, model: String, messages: [ChatMessage]) async throws -> String {
        let request = try makeRequest(apiKey: apiKey, model: model, messages: messages, stream: false)

        do {
            let (data, response) = try await session.data(for: request, delegate: nil)
            try validateDataResponse(response, data: data)

            let chatResponse = try decoder.decode(ChatResponse.self, from: data)
            if let error = chatResponse.error {
                throw mapAPIError(statusCode: 200, message: error.message)
            }

            guard let content = chatResponse.choices?.first?.message?.content,
                  !content.isEmpty else {
                throw OpenRouterClientError.emptyResponse
            }

            return content
        } catch let error as OpenRouterClientError {
            throw error
        } catch let error as URLError {
            throw OpenRouterClientError.networkFailure(error.localizedDescription)
        } catch {
            throw OpenRouterClientError.decodingFailed(error.localizedDescription)
        }
    }

    func completeChatWithTools(apiKey: String, model: String, messages: [OpenRouterChatMessagePayload], tools: [OpenRouterTool]) async throws -> OpenRouterChatResult {
        let request = try makeRequest(apiKey: apiKey, model: model, payloadMessages: messages, stream: false, tools: tools)

        do {
            let (data, response) = try await session.data(for: request, delegate: nil)
            try validateDataResponse(response, data: data)

            let chatResponse = try decoder.decode(ChatResponse.self, from: data)
            if let error = chatResponse.error {
                throw mapAPIError(statusCode: 200, message: error.message)
            }

            guard let message = chatResponse.choices?.first?.message else {
                throw OpenRouterClientError.emptyResponse
            }

            return OpenRouterChatResult(
                content: message.content ?? "",
                toolCalls: message.toolCalls ?? []
            )
        } catch let error as OpenRouterClientError {
            throw error
        } catch let error as URLError {
            throw OpenRouterClientError.networkFailure(error.localizedDescription)
        } catch {
            throw OpenRouterClientError.decodingFailed(error.localizedDescription)
        }
    }

    private func makeRequest(apiKey: String, model: String, messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        let payloadMessages = messages.map {
            OpenRouterChatMessagePayload(role: $0.role.rawValue, content: $0.content)
        }

        return try makeRequest(apiKey: apiKey, model: model, payloadMessages: payloadMessages, stream: stream, tools: nil)
    }

    private func makeRequest(
        apiKey: String,
        model: String,
        payloadMessages: [OpenRouterChatMessagePayload],
        stream: Bool,
        tools: [OpenRouterTool]?
    ) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenRouterClientError.missingAPIKey
        }

        guard let endpoint = URL(string: endpointString) else {
            throw OpenRouterClientError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.openRouterReferer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(Constants.openRouterTitle, forHTTPHeaderField: "X-Title")

        let body = ChatRequest(
            model: model,
            messages: payloadMessages,
            stream: stream,
            tools: tools?.isEmpty == false ? tools : nil,
            toolChoice: tools?.isEmpty == false ? "auto" : nil
        )
        request.httpBody = try encoder.encode(body)

        return request
    }

    private func validateDataResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw errorFromHTTPStatus(httpResponse.statusCode, data: data)
        }
    }

    private func validateStreamingResponse(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var body = Data()
            for try await line in bytes.lines {
                body.append(contentsOf: line.utf8)
                body.append(10)
            }
            throw errorFromHTTPStatus(httpResponse.statusCode, data: body)
        }
    }

    private func errorFromHTTPStatus(_ statusCode: Int, data: Data) -> OpenRouterClientError {
        let message = decodeErrorMessage(from: data)
        return mapAPIError(statusCode: statusCode, message: message)
    }

    private func mapAPIError(statusCode: Int, message: String?) -> OpenRouterClientError {
        switch statusCode {
        case 401, 403:
            return .invalidAPIKey(message)
        case 429:
            return .rateLimited(message)
        case 400, 404, 422:
            return .modelError(message)
        case 500...599:
            return .serverError(statusCode, message)
        default:
            return .serverError(statusCode, message)
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }

        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        return nil
    }

    private static func payload(fromServerSentEventLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("data:") else {
            return nil
        }

        return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OpenRouterChatResult {
    let content: String
    let toolCalls: [OpenRouterToolCall]
}

struct OpenRouterChatMessagePayload: Codable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [OpenRouterToolCall]?

    init(role: String, content: String?, toolCallID: String? = nil, toolCalls: [OpenRouterToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

struct OpenRouterToolCall: Codable, Equatable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Codable, Equatable {
        let name: String
        let arguments: String
    }
}

struct OpenRouterTool: Encodable {
    let type = "function"
    let function: FunctionDefinition

    struct FunctionDefinition: Encodable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
        let additionalProperties = false

        enum CodingKeys: String, CodingKey {
            case type
            case properties
            case required
            case additionalProperties = "additionalProperties"
        }
    }

    struct Property: Encodable {
        let type: String
        let description: String
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [OpenRouterChatMessagePayload]
    let stream: Bool
    let tools: [OpenRouterTool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]?
    let error: ErrorDetail?

    struct Choice: Decodable {
        let message: OpenRouterChatMessagePayload?
    }
}

private struct StreamResponse: Decodable {
    let choices: [Choice]?
    let error: ErrorDetail?

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct ErrorEnvelope: Decodable {
    let error: ErrorDetail?
}

private struct ErrorDetail: Decodable {
    let message: String?
}

private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}
