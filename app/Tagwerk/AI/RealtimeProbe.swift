import Foundation

/// Opens one OpenAI Realtime WebSocket with a short-lived client secret and either speaks a text
/// or transcribes PCM audio. Used by the voice diagnostics only.
enum RealtimeProbe {
    static let endpoint = URL(string: "wss://api.openai.com/v1/realtime")!
    static let sampleRate = 24_000

    struct Result {
        var audio = Data()
        var transcript = ""
        var error: String?
        var events: [String] = []
    }

    /// The `value` of a `client_secrets` answer.
    static func secret(from body: Data) -> String? {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        return (json?["value"] as? String) ?? ((json?["client_secret"] as? [String: Any])?["value"] as? String)
    }

    static func speechSessionBody(voice: String) -> Data {
        json(["session": ["type": "realtime", "model": "gpt-realtime",
                          "instructions": "You read text aloud. Read the user's text exactly, word for word, in its own language. Say nothing else.",
                          "output_modalities": ["audio"],
                          "audio": ["output": ["voice": voice, "format": ["type": "audio/pcm", "rate": sampleRate]]]]])
    }

    static func transcriptionSessionBody() -> Data {
        json(["session": ["type": "transcription",
                          "audio": ["input": ["format": ["type": "audio/pcm", "rate": sampleRate],
                                              "transcription": ["model": "gpt-4o-mini-transcribe"],
                                              "turn_detection": NSNull()]]]])
    }

    /// Speaks `text` and returns the 24 kHz PCM16 audio.
    static func speak(_ text: String, secret: String) async -> Result {
        await run(secret: secret, query: [URLQueryItem(name: "model", value: "gpt-realtime")], timeout: 25,
                  start: [["type": "conversation.item.create",
                           "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]],
                          ["type": "response.create"]]) { event, result in
            switch event["type"] as? String {
            case "response.output_audio.delta":
                if let delta = event["delta"] as? String, let data = Data(base64Encoded: delta) { result.audio.append(data) }
            case "response.output_audio_transcript.done":
                result.transcript = event["transcript"] as? String ?? ""
            case "response.done":
                return true
            default: break
            }
            return false
        }
    }

    /// Transcribes 24 kHz PCM16 mono audio.
    static func transcribe(_ pcm: Data, secret: String) async -> Result {
        var start: [[String: Any]] = stride(from: 0, to: pcm.count, by: 32_000).map { offset in
            ["type": "input_audio_buffer.append", "audio": pcm.subdata(in: offset..<min(offset + 32_000, pcm.count)).base64EncodedString()]
        }
        start.append(["type": "input_audio_buffer.commit"])
        return await run(secret: secret, query: [], timeout: 25, start: start) { event, result in
            switch event["type"] as? String {
            case "conversation.item.input_audio_transcription.completed":
                result.transcript = event["transcript"] as? String ?? ""
                return true
            case "conversation.item.input_audio_transcription.failed":
                result.error = "transcription failed"
                return true
            default: return false
            }
        }
    }

    /// PCM16 resampled linearly to 24 kHz.
    static func resample(_ samples: [Int16], from rate: Int) -> Data {
        guard rate > 0, !samples.isEmpty else { return Data() }
        let count = Int(Double(samples.count) * Double(sampleRate) / Double(rate))
        var data = Data(capacity: count * 2)
        for index in 0..<count {
            let position = Double(index) * Double(rate) / Double(sampleRate)
            let lower = min(Int(position), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = position - Double(lower)
            let value = Int16(Double(samples[lower]) * (1 - fraction) + Double(samples[upper]) * fraction)
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: Private

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    private static func run(secret: String, query: [URLQueryItem], timeout: TimeInterval, start: [[String: Any]],
                            handle: @escaping ([String: Any], inout Result) -> Bool) async -> Result {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        var result = Result()
        do {
            for message in start {
                try await socket.send(.string(String(decoding: json(message), as: UTF8.self)))
            }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
                    group.addTask { try await socket.receive() }
                    group.addTask { try await Task.sleep(for: .seconds(max(0.1, deadline.timeIntervalSinceNow))); return nil }
                    let first = try await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                guard let message else { result.error = "timeout"; break }
                guard case .string(let text) = message,
                      let event = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { continue }
                let type = event["type"] as? String ?? "?"
                if !result.events.contains(type) { result.events.append(type) }
                if type == "error" {
                    let error = event["error"] as? [String: Any]
                    result.error = [error?["code"] as? String, (error?["message"] as? String).map { String($0.prefix(140)) }]
                        .compactMap { $0 }.joined(separator: ": ")
                    break
                }
                if handle(event, &result) { break }
            }
        } catch {
            let status = (socket.response as? HTTPURLResponse)?.statusCode
            result.error = status.map { "HTTP \($0)" } ?? error.localizedDescription
        }
        return result
    }
}
