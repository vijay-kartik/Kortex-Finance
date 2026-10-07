import Foundation
import Security

/// The models Kortex for Mac uses through Vercel AI Gateway, picked in Settings › AI.
public enum AIModel: String, CaseIterable, Sendable, Identifiable {
    /// Reads scanned statements and tables well, with structured output, at a few cents a statement.
    case sonnet = "anthropic/claude-sonnet-5.5"
    /// For statements Sonnet struggles with: blurry scans, dense layouts. About twice the price.
    case opus = "anthropic/claude-opus-5.5"

    public static let `default` = AIModel.sonnet
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sonnet: "Claude Sonnet 5.5 (recommended)"
        case .opus: "Claude Opus 5.5 (hardest scans)"
        }
    }
}

/// The AI Gateway key, kept in the macOS Keychain, never in the app or the repo.
public enum AIKeyStore {
    private static let service = "dev.kortex.mac.ai-gateway"
    private static let account = "AI_GATEWAY_API_KEY"

    public static var key: String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static var hasKey: Bool { key?.isEmpty == false }

    /// Saves the key, replacing any; an empty key removes it.
    @discardableResult
    public static func save(_ key: String) -> Bool {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var add = query
        add[kSecValueData] = Data(trimmed.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

public enum AIGatewayError: LocalizedError {
    case noKey
    case http(Int, String)
    case emptyAnswer
    case unreadableAnswer(String)

    public var errorDescription: String? {
        switch self {
        case .noKey: "Add your Vercel AI Gateway key in Settings › AI first."
        case .http(401, _), .http(403, _): "The AI Gateway key was refused. Check it in Settings › AI."
        case .http(429, _): "The AI Gateway is rate-limiting requests. Try again in a minute."
        case .http(let code, let body): "The AI Gateway answered \(code): \(body.prefix(200))"
        case .emptyAnswer: "The model didn't answer."
        case .unreadableAnswer(let why): "The model's answer couldn't be read: \(why)"
        }
    }
}

/// Vercel AI Gateway's OpenAI-compatible chat completions (https://ai-gateway.vercel.sh/v1), with
/// images as data URLs and the answer held to a JSON schema (structured output).
public struct AIGateway: Sendable {
    public static let baseURL = URL(string: "https://ai-gateway.vercel.sh/v1")!

    public struct Image: Sendable {
        public let data: Data
        public let mimeType: String
        public init(data: Data, mimeType: String) {
            self.data = data
            self.mimeType = mimeType
        }
    }

    private let key: String
    private let session: URLSession

    public init(key: String? = AIKeyStore.key) throws {
        guard let key, !key.isEmpty else { throw AIGatewayError.noKey }
        self.key = key
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 240
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    /// One user turn of instructions and images; the reply decoded as `T` from JSON matching `schema`.
    public func structured<T: Decodable>(_ type: T.Type, model: AIModel, system: String, prompt: String, images: [Image],
                                         schemaName: String, schema: [String: Any], maxTokens: Int = 16_000) async throws -> T {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for image in images {
            content.append(["type": "image_url", "image_url": ["url": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())", "detail": "high"]])
        }
        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": [["role": "system", "content": system], ["role": "user", "content": content]],
            "max_tokens": maxTokens,
            "temperature": 0,
            "response_format": ["type": "json_schema", "json_schema": ["name": schemaName, "strict": true, "schema": schema]],
        ]
        let text = try await complete(body)
        guard let data = Self.json(in: text).data(using: .utf8) else { throw AIGatewayError.unreadableAnswer("not text") }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIGatewayError.unreadableAnswer(error.localizedDescription)
        }
    }

    /// A one-word reply, to check the key and model from Settings.
    public func ping(model: AIModel) async throws -> String {
        try await complete([
            "model": model.rawValue,
            "messages": [["role": "user", "content": "Reply with the single word: ready"]],
            "max_tokens": 10,
        ])
    }

    private func complete(_ body: [String: Any]) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIGatewayError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((decoded?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
        guard let text = message?["content"] as? String, !text.isEmpty else { throw AIGatewayError.emptyAnswer }
        return text
    }

    /// The JSON object in a reply, should a model wrap it in a code fence.
    static func json(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return text }
        return String(text[start...end])
    }
}
