import Combine
import Foundation
import SwiftUI
import UIKit

/// Where the local profile came from. Only `.local` can be produced by the
/// shipped app; the other cases are placeholders for a future authorized sign-in.
enum ProfileProvider: String, Codable, CaseIterable, Identifiable {
    case local
    case wechat
    case alipay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地资料"
        case .wechat: return "微信"
        case .alipay: return "支付宝"
        }
    }

    var symbolName: String {
        switch self {
        case .local: return "internaldrive"
        case .wechat: return "bubble.left.and.bubble.right.fill"
        case .alipay: return "yensign.circle.fill"
        }
    }

    var requiresRemoteAuthorization: Bool {
        self != .local
    }
}

struct LocalProfile: Codable, Equatable {
    static let defaultNickname = "本地用户"

    var nickname: String
    var avatarData: Data?
    var provider: ProfileProvider
    var updatedAt: Date

    init(
        nickname: String = LocalProfile.defaultNickname,
        avatarData: Data? = nil,
        provider: ProfileProvider = .local,
        updatedAt: Date = Date()
    ) {
        self.nickname = nickname
        self.avatarData = avatarData
        self.provider = provider
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case nickname
        case avatarData
        case provider
        case updatedAt
    }

    /// Tolerates older or partially written JSON instead of dropping the whole
    /// profile because one optional field is missing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedNickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        let trimmed = storedNickname?.trimmingCharacters(in: .whitespacesAndNewlines)

        nickname = trimmed?.isEmpty == false ? trimmed! : LocalProfile.defaultNickname
        avatarData = try container.decodeIfPresent(Data.self, forKey: .avatarData)
        provider = try container.decodeIfPresent(ProfileProvider.self, forKey: .provider) ?? .local
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(avatarData, forKey: .avatarData)
        try container.encode(provider, forKey: .provider)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Single source of truth for the local-only profile. Nothing here sends data to
/// WeChat, Alipay, iCloud, or any other service.
@MainActor
final class LocalProfileStore: ObservableObject {
    static let shared = LocalProfileStore()

    @Published private(set) var profile: LocalProfile

    /// Surfaced by the profile menu when the on-disk write fails. The in-memory
    /// profile still updates so the user does not lose the current edit.
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folder = root.appendingPathComponent("LedgerBox", isDirectory: true)
        let url = folder.appendingPathComponent("local-profile.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.fileURL = url
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.profile = LocalProfileStore.loadProfile(at: url, decoder: decoder)
        self.persistenceError = nil
    }

    func updateNickname(_ nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        mutate { profile in
            profile.nickname = trimmed
        }
    }

    func updateAvatar(_ data: Data?) {
        mutate { profile in
            if let data, !data.isEmpty {
                profile.avatarData = data
            } else {
                profile.avatarData = nil
            }
        }
    }

    /// Selects the profile source. Remote providers are intentionally rejected:
    /// switching to WeChat/Alipay requires a real SDK authorization round trip,
    /// not a local enum change that would imply a fake sign-in.
    func setProvider(_ provider: ProfileProvider) {
        guard provider == .local else {
            return
        }

        mutate { profile in
            profile.provider = .local
        }
    }

    private func mutate(_ change: (inout LocalProfile) -> Void) {
        var next = profile
        change(&next)

        guard next != profile else {
            return
        }

        next.updatedAt = Date()
        profile = next
        persist()
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
        } catch {
            persistenceError = "本地资料保存失败：\(error.localizedDescription)"
        }
    }

    private static func loadProfile(at url: URL, decoder: JSONDecoder) -> LocalProfile {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? decoder.decode(LocalProfile.self, from: data)
        else {
            return LocalProfile()
        }

        return decoded
    }
}

// MARK: - Remote authorization contract
//
// Real WeChat sign-in needs an AppID, the WeChat OpenSDK, a registered URL
// scheme / Universal Link, and a server endpoint that exchanges the returned
// code for an access token and openid. Real Alipay sign-in likewise needs an
// AppID, the AlipaySDK, and a server that signs the request and exchanges the
// auth code. This repository ships no AppID, SDK dependency, credentials, or
// backend, so no provider implementation is supplied and the UI must keep those
// buttons disabled. Never fabricate an AuthorizedProfile from local input.

/// The result that a real, server-validated provider flow would hand back.
struct AuthorizedProfile: Equatable {
    let provider: ProfileProvider
    let accountID: String
    let nickname: String
    let avatarURL: URL?
}

enum ProfileAuthorizationError: LocalizedError {
    case notConfigured(ProfileProvider)
    case userCancelled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "\(provider.displayName)登录尚未配置：需要 AppID、官方 SDK 与服务端换取 token。"
        case .userCancelled:
            return "已取消授权。"
        case .invalidResponse:
            return "授权服务返回了无效资料。"
        }
    }
}

protocol ProfileAuthorizing {
    var provider: ProfileProvider { get }
    var isConfigured: Bool { get }

    func authorize() async throws -> AuthorizedProfile
}

// MARK: - Avatar

struct AvatarView: View {
    private let nickname: String
    private let avatarData: Data?
    private let size: CGFloat

    @Environment(\.ledgerTheme) private var theme

    init(nickname: String, avatarData: Data?, size: CGFloat = 64) {
        self.nickname = nickname
        self.avatarData = avatarData
        self.size = size
    }

    init(profile: LocalProfile, size: CGFloat = 64) {
        self.init(
            nickname: profile.nickname,
            avatarData: profile.avatarData,
            size: size
        )
    }

    var body: some View {
        ZStack {
            if let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Circle()
                    .fill(theme.surfaceElevated)

                Text(initial)
                    .font(.system(size: max(16, size * 0.38), weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accentText)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(theme.separator, lineWidth: theme.hairline)
        }
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var avatarImage: UIImage? {
        guard let avatarData else {
            return nil
        }
        return UIImage(data: avatarData)
    }

    private var initial: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map(String.init) ?? "?"
    }

    private var accessibilityLabel: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "本地头像" : "\(trimmed)的头像"
    }
}
