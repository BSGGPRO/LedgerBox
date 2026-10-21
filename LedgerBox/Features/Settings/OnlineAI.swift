import Foundation
import Security

// MARK: - Configuration

enum OnlineAIConfig {
    static let enabledKey = "onlineAI.enabled"
    static let endpointKey = "onlineAI.endpoint"
    static let modelKey = "onlineAI.model"

    static let defaultEndpoint = "https://api.deepseek.com/v1"
    static let defaultModel = "deepseek-chat"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var endpoint: String {
        guard let value = UserDefaults.standard.string(forKey: endpointKey) else {
            return defaultEndpoint
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var model: String {
        guard let value = UserDefaults.standard.string(forKey: modelKey) else {
            return defaultModel
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var apiKey: String {
        KeychainStore.read() ?? ""
    }

    static var isConfigured: Bool {
        !endpoint.isEmpty && !model.isEmpty
    }
}

// MARK: - Keychain

enum KeychainStore {
    private static var service: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.example.ledgerbox"
        return "\(bundleID).onlineai"
    }

    private static let account = "api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        delete()

        guard !value.isEmpty else {
            return true
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Messages

struct OnlineAIMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Client

enum OnlineAIError: LocalizedError {
    case disabled
    case notConfigured
    case invalidEndpoint
    case http(Int, String)
    case emptyReply
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "联网 AI 还没有开启。请到 设置 → 联网 AI 打开开关。"
        case .notConfigured:
            return "请先填写接口地址和模型名称。"
        case .invalidEndpoint:
            return "接口地址无效：只支持 https://，并且需要以 /chat/completions 结尾或能自动补全。"
        case .http(let code, let message):
            return "接口返回 \(code)：\(message)"
        case .emptyReply:
            return "接口返回了空内容。"
        case .decoding(let message):
            return "返回内容无法解析：\(message)"
        }
    }
}

final class OnlineAIClient {
    static let shared = OnlineAIClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func send(_ messages: [OnlineAIMessage]) async throws -> String {
        guard OnlineAIConfig.isEnabled else {
            throw OnlineAIError.disabled
        }
        guard OnlineAIConfig.isConfigured else {
            throw OnlineAIError.notConfigured
        }

        let endpoint = try Self.chatURL(from: OnlineAIConfig.endpoint)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LedgerBox/0.3.0", forHTTPHeaderField: "User-Agent")

        let key = OnlineAIConfig.apiKey
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatRequest(
            model: OnlineAIConfig.model,
            messages: [Self.systemMessage] + messages.suffix(16).map {
                WireMessage(role: $0.role.rawValue, content: $0.content)
            },
            temperature: 0.2,
            stream: false,
            maxTokens: 900
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OnlineAIError.emptyReply
        }

        guard (200...299).contains(http.statusCode) else {
            let message = Self.apiErrorMessage(from: data)
            throw OnlineAIError.http(http.statusCode, message)
        }

        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            let content = decoded.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else {
                throw OnlineAIError.emptyReply
            }
            return content
        } catch let error as OnlineAIError {
            throw error
        } catch {
            throw OnlineAIError.decoding(error.localizedDescription)
        }
    }

    func test() async throws -> String {
        try await send([
            OnlineAIMessage(role: .user, content: "只回复 OK，不要解释。")
        ])
    }

    static func chatURL(from raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty
        else {
            throw OnlineAIError.invalidEndpoint
        }

        var path = components.path
        if path.hasSuffix("/chat/completions") {
            // Already a full endpoint.
        } else {
            if path.hasSuffix("/") {
                path += "chat/completions"
            } else {
                path += "/chat/completions"
            }
        }
        components.path = path

        guard let url = components.url else {
            throw OnlineAIError.invalidEndpoint
        }
        return url
    }

    private static var systemMessage: WireMessage {
        WireMessage(
            role: "system",
            content: """
            你是 LedgerBox 的记账助手。用简体中文回答。
            只讨论记账、分类、预算、储蓄和消费习惯；不要编造用户的账本数据。
            不要替用户直接写账；给出建议后让用户自己确认。
            涉及投资时只做风险提示，不给具体买卖指令。
            """
        )
    }

    private static func apiErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(300))
        }
        return "未知错误"
    }
}

// MARK: - Wire types

private struct WireMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [WireMessage]
    let temperature: Double
    let stream: Bool
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case stream
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}
