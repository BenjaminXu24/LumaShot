import Foundation

enum DeepSeekClientError: Error, Equatable {
    case emptyAPIKey
    case invalidResponse
    case httpStatus(Int)
    case emptyTranslation
    case transport
}

/// DeepSeek Chat Completions. The body is text only; callers must already have consent and a Keychain key.
enum DeepSeekTranslation {
    /// Official fast chat model (`deepseek-flash`, DeepSeek-V4.1-Flash) from https://api.deepseek.com as of 2026-10-24.
    /// `deepseek-chat` was discontinued. Thinking defaults to on, so short translations disable it explicitly.
    static let modelID = "deepseek-flash"
    static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    static let temperature = 0.2

    struct ChatBody: Codable, Equatable {
        struct Message: Codable, Equatable {
            var role: String
            var content: String
        }

        struct Thinking: Codable, Equatable {
            var type: String
        }

        var model: String
        var messages: [Message]
        var thinking: Thinking
        var reasoning_effort: String
        var stream: Bool
        var temperature: Double
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 45
        return configuration
    }

    static func systemPrompt(source: TranslationLanguage?, target: TranslationLanguage) -> String {
        let sourceInstruction: String
        if let source {
            sourceInstruction = "The source language is \(source.englishName)."
        } else {
            sourceInstruction = "Detect whether the source is Simplified Chinese, English, or Filipino."
        }
        return """
        You translate text. \(sourceInstruction) Translate into \(target.englishName). \
        Preserve line breaks and meaning. Return only the translation, with no quotes, labels, or notes.
        """
    }

    static func body(text: String, source: TranslationLanguage?, target: TranslationLanguage, model: String = modelID) -> ChatBody {
        ChatBody(
            model: model,
            messages: [
                ChatBody.Message(role: "system", content: systemPrompt(source: source, target: target)),
                ChatBody.Message(role: "user", content: text)
            ],
            thinking: ChatBody.Thinking(type: "disabled"),
            reasoning_effort: "none",
            stream: false,
            temperature: temperature
        )
    }

    /// Builds the HTTP request. Do not log it: the Authorization header holds the API key and the body holds the user's text.
    static func makeRequest(
        text: String,
        source: TranslationLanguage?,
        target: TranslationLanguage,
        apiKey: String,
        model: String = modelID
    ) throws -> URLRequest {
        let encoded = try JSONEncoder().encode(body(text: text, source: source, target: target, model: model))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = encoded
        return request
    }

    static func parse(data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else { throw DeepSeekClientError.httpStatus(statusCode) }
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw DeepSeekClientError.invalidResponse
        }
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw DeepSeekClientError.emptyTranslation }
        return text
    }

    static func userMessage(for error: Error) -> String {
        guard let error = error as? DeepSeekClientError else {
            return "在线翻译没有完成。识别出的文字仍只在这台 Mac 上。"
        }
        switch error {
        case .emptyAPIKey:
            return "还没有可用的 DeepSeek API Key。请在设置里填写，它只会写入钥匙串。"
        case .invalidResponse, .emptyTranslation:
            return "DeepSeek 没有返回译文。请再试一次。"
        case .transport:
            return "无法连接 DeepSeek。请检查网络后再试。文字没有被保存。"
        case .httpStatus(let code):
            switch code {
            case 401:
                return "DeepSeek 没有接受钥匙串里的 API Key。请在设置中更新。"
            case 402:
                return "DeepSeek 账户余额不足，这次没有得到译文。"
            case 429:
                return "DeepSeek 请求过于频繁，请稍后再试。"
            default:
                return "在线翻译失败（HTTP \(code)）。文字没有被保存。"
            }
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }

            var message: Message
        }

        var choices: [Choice]
    }
}

protocol TranslationTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTranslationTransport: TranslationTransport {
    var session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: DeepSeekTranslation.sessionConfiguration())
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DeepSeekClientError.invalidResponse }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw error
        }
    }
}

struct DeepSeekTranslator {
    var transport: TranslationTransport

    init(transport: TranslationTransport = URLSessionTranslationTransport()) {
        self.transport = transport
    }

    func translate(
        text: String,
        source: TranslationLanguage?,
        target: TranslationLanguage,
        apiKey: String
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekClientError.emptyAPIKey }
        try Task.checkCancellation()
        let request = try DeepSeekTranslation.makeRequest(text: text, source: source, target: target, apiKey: trimmedKey)
        do {
            try Task.checkCancellation()
            let (data, http) = try await transport.send(request)
            try Task.checkCancellation()
            return try DeepSeekTranslation.parse(data: data, statusCode: http.statusCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DeepSeekClientError {
            throw error
        } catch {
            throw DeepSeekClientError.transport
        }
    }
}
