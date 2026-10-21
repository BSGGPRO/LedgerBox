import CoreData
import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ProfileMenuView: View {
    @Environment(\.ledgerTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var themeManager: ThemeManager

    @ObservedObject private var profileStore = LocalProfileStore.shared

    @State private var showingNicknameEditor = false
    @State private var nicknameDraft = ""
    @State private var showingSettings = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingAvatar = false
    @State private var photoError: String?

    private var profile: LocalProfile {
        profileStore.profile
    }

    var body: some View {
        GlassHeaderHost(
            title: "账户",
            subtitle: "本地资料与偏好",
            trailing: {
                closeButton
            }
        ) {
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                profileCard
                localActionsCard
                providerCard
                privacyCard
                aboutCard
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.top, theme.cardSpacing)
            .padding(.bottom, theme.sectionSpacing)
        }
        .tint(theme.accentText)
        .onAppear {
            nicknameDraft = profile.nickname
        }
        .onChange(of: profile.nickname) { _, newValue in
            if !showingNicknameEditor {
                nicknameDraft = newValue
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            loadAvatar(from: item)
        }
        .alert("修改昵称", isPresented: $showingNicknameEditor) {
            TextField("昵称", text: $nicknameDraft)

            Button("取消", role: .cancel) {
                nicknameDraft = profile.nickname
            }

            Button("保存") {
                profileStore.updateNickname(nicknameDraft)
            }
        } message: {
            Text("昵称只保存在本机，不会同步到微信或支付宝。")
        }
        .sheet(isPresented: $showingSettings) {
            // SettingsView owns its own NavigationStack. Presenting it in a
            // sheet avoids nesting navigation stacks or pushing a root view.
            SettingsView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(themeManager)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭账户页面")
    }

    // MARK: - Identity

    private var profileCard: some View {
        LedgerCard {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: theme.cardSpacing) {
                        AvatarView(profile: profile, size: 68)
                        profileIdentity
                    }
                } else {
                    HStack(alignment: .center, spacing: theme.spacing) {
                        AvatarView(profile: profile, size: 68)
                        profileIdentity
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var profileIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.nickname)
                .font(theme.screenTitleFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.smallSpacing) {
                    providerSource
                    LedgerTag("仅本机", tint: theme.income)
                }

                VStack(alignment: .leading, spacing: 4) {
                    providerSource
                    LedgerTag("仅本机", tint: theme.income)
                }
            }

            if let error = profileStore.persistenceError {
                Text(error)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.expense)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var providerSource: some View {
        Label("来源 · \(profile.provider.displayName)", systemImage: profile.provider.symbolName)
            .font(theme.captionFont)
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: - Local actions

    private var localActionsCard: some View {
        LedgerCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    nicknameDraft = profile.nickname
                    showingNicknameEditor = true
                } label: {
                    actionRow(
                        icon: "pencil",
                        tint: theme.accentText,
                        title: "修改昵称",
                        subtitle: "只保存在本机，不上传"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开昵称编辑框")

                hairline

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    actionRow(
                        icon: "photo.on.rectangle.angled",
                        tint: theme.accentText,
                        title: isLoadingAvatar ? "正在读取照片…" : "从相册选择头像",
                        subtitle: "系统照片选择器 · 仅保存到本机",
                        showsProgress: isLoadingAvatar
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingAvatar)
                .accessibilityLabel("从相册选择头像")
                .accessibilityHint("打开系统照片选择器，图片只保存在本机")

                if let photoError {
                    Text(photoError)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.expense)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.cardPadding)
                        .padding(.bottom, theme.smallSpacing)
                }

                hairline

                Button {
                    showingSettings = true
                } label: {
                    actionRow(
                        icon: "gearshape",
                        tint: theme.accentText,
                        title: "设置",
                        subtitle: "主题、强调色、模板、导出与关于"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开 LedgerBox 设置")
            }
        }
    }

    private func actionRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: theme.cardSpacing) {
            LedgerIconBadge(systemName: icon, tint: tint, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(0)

            Spacer(minLength: theme.smallSpacing)

            if showsProgress {
                ProgressView()
                    .tint(theme.accentText)
            } else {
                Image(systemName: "chevron.right")
                    .font(theme.controlIconFont)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.horizontal, theme.cardPadding)
        .padding(.vertical, 6)
        .frame(minHeight: theme.rowMinHeight)
        .contentShape(Rectangle())
    }

    // MARK: - Providers

    private var providerCard: some View {
        LedgerCard(surface: .elevated) {
            VStack(alignment: .leading, spacing: theme.cardSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
                    Text("账号来源")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: theme.smallSpacing)

                    LedgerTag("未接入", tint: theme.warning)
                }

                Text("当前仅支持本地资料。微信 / 支付宝登录需要官方授权，未配置时不会读取任何第三方账号信息。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: theme.smallSpacing) {
                    providerButton(.wechat)
                    providerButton(.alipay)
                }

                Label(
                    "需要 AppID/SDK/服务端，当前仅本地资料",
                    systemImage: "info.circle"
                )
                .font(theme.captionFont)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerButton(_ provider: ProfileProvider) -> some View {
        Button {
            // Intentionally empty. There is no configured provider implementation;
            // enabling this would fake an authorization flow.
        } label: {
            HStack(spacing: 6) {
                Image(systemName: provider.symbolName)
                    .font(theme.controlIconFont)

                Text(provider.displayName)
                    .font(theme.captionFont)
                    .lineLimit(1)

                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: theme.minTapTarget)
            .background(theme.surface, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.separator, lineWidth: theme.hairline)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.55)
        .accessibilityLabel("\(provider.displayName)登录")
        .accessibilityHint("未配置，需要 AppID/SDK/服务端，当前仅本地资料")
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.cardSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
                    Label("数据与隐私", systemImage: "lock.shield")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: theme.smallSpacing)

                    LedgerTag("本地", tint: theme.income)
                }

                Text("昵称、头像与来源只保存在本机 Application Support/LedgerBox/local-profile.json。它们不会上传，也不会用于广告或第三方分析。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("账本数据仍由 Core Data 保存在本机。删除 App 会一并移除这些本地资料。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.cardSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("关于 LedgerBox")
                            .font(theme.sectionTitleFont)
                            .foregroundStyle(theme.primaryText)
                            .accessibilityAddTraits(.isHeader)

                        Text("本地优先 · iOS 17+ · SwiftUI")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer(minLength: theme.smallSpacing)

                    LedgerTag("v\(appVersion)")
                }

                hairline

                Link(destination: repositoryURL) {
                    HStack(spacing: theme.cardSpacing) {
                        LedgerIconBadge(
                            systemName: "chevron.left.forwardslash.chevron.right",
                            tint: theme.accentText
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("GitHub 开源地址")
                                .font(theme.bodyFont.weight(.medium))
                                .foregroundStyle(theme.primaryText)

                            Text("BSGGPRO / LedgerBox · MIT")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: theme.smallSpacing)

                        Image(systemName: "arrow.up.right")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .frame(minHeight: theme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("GitHub 开源地址")
                .accessibilityHint("在浏览器打开 LedgerBox 仓库")
            }
        }
    }

    // MARK: - Media

    private func loadAvatar(from item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        isLoadingAvatar = true
        photoError = nil

        Task { @MainActor in
            defer {
                isLoadingAvatar = false
                selectedPhoto = nil
            }

            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let prepared = Self.preparedAvatarData(from: data)
                else {
                    photoError = "无法读取这张图片，请换一张再试。"
                    return
                }

                profileStore.updateAvatar(prepared)
            } catch {
                photoError = "读取相册图片失败：\(error.localizedDescription)"
            }
        }
    }

    /// Keeps the profile JSON small and avoids retaining the full camera image.
    /// The system picker already runs out of process, so no photo permission
    /// prompt or library enumeration happens here.
    private static func preparedAvatarData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else {
            return nil
        }

        let scale = min(1, 512 / longestSide)
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: 0.86)
    }

    // MARK: - Helpers

    private var hairline: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: theme.hairline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/BSGGPRO/LedgerBox")!
    }
}
