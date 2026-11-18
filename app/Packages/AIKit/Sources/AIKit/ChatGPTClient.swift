import Foundation

/// Calls the OpenAI API with the ChatGPT plan token: model list and streamed Responses.
///
/// Every call sends `store:false` and `stream:true`, no `max_output_tokens`, no `temperature`
/// and no `previous_response_id`. A response counts as successful only with `response.completed`.
public final class ChatGPTClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    private let session: ChatGPTSessionStore
    private let transport: AIHTTPTransport
    private let baseURL: URL
    public let options: AIRequestOptions

    public init(session: ChatGPTSessionStore, transport: AIHTTPTransport, baseURL: URL = ChatGPTClient.defaultBaseURL,
                options: AIRequestOptions = AIRequestOptions()) {
        self.session = session
        self.transport = transport
        self.baseURL = baseURL
        self.options = options
    }

    // MARK: Models

    /// The selectable models in server order.
    public func models() async throws -> [AIModel] {
        let url = baseURL.appending(path: "models")
        let data = try await withAuthorization { token -> Attempt<Data> in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await self.send { try await self.transport.data(for: request) }
            return response.statusCode == 200 ? .success(data) : .failure(status: response.statusCode, body: data)
        }
        return Self.listedModels(data)
    }

    static func listedModels(_ data: Data) -> [AIModel] {
        struct Level: Decodable {
            let effort: String?
            init(from decoder: Decoder) throws {
                // Levels arrive as objects with "effort" or as plain strings.
                if let text = try? decoder.singleValueContainer().decode(String.self) {
                    effort = text
                } else {
                    effort = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .effort)
                }
            }
            enum CodingKeys: String, CodingKey { case effort }
        }
        struct Entry: Decodable {
            let slug: String
            let display_name: String?
            let visibility: String?
            let supported_reasoning_levels: [Level]?
            let default_reasoning_level: String?
        }
        struct Body: Decodable { let models: [Entry] }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return [] }
        return body.models
            .filter { $0.visibility == "list" }
            .map { AIModel(slug: $0.slug, displayName: $0.display_name ?? $0.slug,
                           reasoningLevels: ($0.supported_reasoning_levels ?? []).compactMap(\.effort),
                           defaultReasoning: $0.default_reasoning_level) }
    }

    // MARK: Responses

    /// Streams one response. Cancelling the consumer cancels the request.
    public func respond(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                        jsonSchema: (name: String, schema: Data)?) -> AsyncThrowingStream<StreamEvent, Error> {
        let body: Data
        do {
            body = try Self.requestBody(model: model, instructions: instructions, input: input, tools: tools, jsonSchema: jsonSchema,
                                        reasoningEffort: options.reasoningEffort)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let url = baseURL.appending(path: "responses")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await self.withAuthorization { token -> Attempt<LineStream> in
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.httpBody = body
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (lines, response) = try await self.send { try await self.transport.lines(for: request) }
                        guard response.statusCode == 200 else {
                            // Errors come as a JSON body, also on the stream endpoint.
                            var text = ""
                            for try await line in lines { text += line + "\n" }
                            return .failure(status: response.statusCode, body: Data(text.utf8))
                        }
                        return .success(LineStream(lines: lines))
                    }
                    var parser = ResponsesStreamParser()
                    do {
                        for try await line in stream.lines {
                            for event in try parser.consume(line) { continuation.yield(event) }
                            if parser.isCompleted { break }
                        }
                    } catch let error as ChatGPTError {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // The connection broke mid-stream (network change, app in background).
                        throw ChatGPTError.incomplete
                    }
                    guard parser.isCompleted else { throw ChatGPTError.incomplete }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The JSON body of a Responses call.
    static func requestBody(model: String, instructions: String, input: [InputItem], tools: [ToolDefinition],
                            jsonSchema: (name: String, schema: Data)?, reasoningEffort: String? = nil) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input.map(\.requestJSON),
            "store": false,
            "stream": true,
        ]
        if let reasoningEffort { body["reasoning"] = ["effort": reasoningEffort] }
        if !tools.isEmpty {
            body["tools"] = try tools.map { try $0.requestJSON() }
        }
        if let jsonSchema {
            body["text"] = ["format": [
                "type": "json_schema",
                "name": jsonSchema.name,
                "schema": try JSONSerialization.jsonObject(with: jsonSchema.schema),
                "strict": true,
            ]]
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    // MARK: Plain requests

    static let tokenHosts: Set<String> = ["api.openai.com", "chatgpt.com"]

    /// Status code and body of a plain request.
    public struct Reply: Sendable {
        public let status: Int
        public let body: Data
    }

    /// Posts `body` to `url` with the plan token. Any status is returned; only a 401 triggers one refresh.
    /// Used by the voice endpoints and their diagnostics.
    public func post(_ url: URL, body: Data, contentType: String) async throws -> Reply {
        // The plan token goes only to OpenAI's own hosts.
        guard url.scheme == "https", let host = url.host(), Self.tokenHosts.contains(host) else { throw ChatGPTError.server(0, "host_not_allowed") }
        let accountID = await session.accountID
        return try await withAuthorization { token -> Attempt<Reply> in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            if let accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
            let (data, response) = try await self.send { try await self.transport.data(for: request) }
            return response.statusCode == 401 ? .failure(status: 401, body: data) : .success(Reply(status: response.statusCode, body: data))
        }
    }

    /// A `multipart/form-data` body with text fields and one file part named `file`.
    public static func multipart(fields: [(String, String)], file: Data, fileName: String, mimeType: String,
                                 boundary: String = UUID().uuidString) -> (body: Data, contentType: String) {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (body, "multipart/form-data; boundary=\(boundary)")
    }

    // MARK: Private

    /// Outcome of one authorized attempt: the value, or the status and JSON error body.
    private enum Attempt<Value: Sendable>: Sendable {
        case success(Value)
        case failure(status: Int, body: Data)
    }

    private struct LineStream: @unchecked Sendable {
        let lines: AsyncThrowingStream<String, Error>
    }

    /// Runs `operation` with a valid token. On HTTP 401 the error code is checked first:
    /// `subscription_sharing_invalid_user` is never retried; otherwise the token is refreshed once.
    private func withAuthorization<Value: Sendable>(
        _ operation: @Sendable (String) async throws -> Attempt<Value>
    ) async throws -> Value {
        var token = try await session.validAccessToken()
        var retried = false
        while true {
            switch try await operation(token) {
            case .success(let value):
                return value
            case .failure(let status, let body):
                let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
                let code = ChatGPTAuth.errorCode(in: json)
                if status == 401, code != "subscription_sharing_invalid_user", !retried {
                    retried = true
                    token = try await session.handleUnauthorized(failedToken: token)
                    continue
                }
                throw ResponsesStreamParser.error(for: code, status: status)
            }
        }
    }

    /// Maps transport failures before a response to `.network`; cancellation stays cancellation.
    private func send<Value>(_ operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ChatGPTError.network
        }
    }
}
