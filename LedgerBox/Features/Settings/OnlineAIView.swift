import SwiftUI

// MARK: - Settings

struct OnlineAISettingsView: View {
    @Environment(\.ledgerTheme) private var theme

    @AppStorage(OnlineAIConfig.enabledKey) private var enabled = false
    @AppStorage(OnlineAIConfig.endpointKey) private var endpoint = OnlineAIConfig.defaultEndpoint
    @AppStorage(OnlineAIConfig.modelKey) private var model = OnlineAIConfig.defaultModel

    @State private var apiKey = ""
    @State private var keyStatus: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing) {
                introCard
                configurationCard
                privacyCard
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.vertical, theme.spacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("联网 AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = KeychainStore.read() ?? ""
        }
        .alert(
            "联网 AI",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var introCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(theme.rowIconFont)
                        .foregroundStyle(theme.accent)

                    Text("可选联网")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text(enabled ? "已开启" : "默认关闭")
                        .font(theme.badgeFont)
                        .foregroundStyle(enabled ? theme.income : theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (enabled ? theme.income : theme.secondaryText).opacity(0.12),
                            in: Capsule()
                        )
                }

                Text("本地小 AI 仍然负责解析和提示；联网只用于你主动发送的问答。账本数据不会自动上传。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var configurationCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("允许联网", isOn: $enabled)
                    .font(theme.bodyFont)
                    .tint(theme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("接口地址")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)

                    TextField("https://api.deepseek.com/v1", text: $endpoint)
                        .font(theme.captionFont)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(10)
                        .background(theme.surfaceElevated, in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("模型名称")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)

                    TextField("deepseek-chat", text: $model)
                        .font(theme.captionFont)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(theme.surfaceElevated, in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)

                    SecureField("sk-...（可留空）", text: $apiKey)
                        .font(theme.captionFont)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(theme.surfaceElevated, in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button {
                        saveKey()
                    } label: {
                        Label("保存密钥", systemImage: "key.fill")
                            .font(theme.captionFont)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        testConnection()
                    } label: {
                        Group {
                            if isTesting {
                                ProgressView()
                            } else {
                                Label("测试连接", systemImage: "bolt.horizontal")
                            }
                        }
                        .font(theme.captionFont)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(isTesting)
                }

                if let keyStatus {
                    Text(keyStatus)
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.income)
                }

                if let testResult {
                    Text(testResult)
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(theme.separator)

                Menu {
                    Button("DeepSeek") {
                        endpoint = "https://api.deepseek.com/v1"
                        model = "deepseek-chat"
                    }
                    Button("OpenAI") {
                        endpoint = "https://api.openai.com/v1"
                        model = "gpt-4o-mini"
                    }
                    Button("自定义") {
                        endpoint = ""
                        model = ""
                    }
                } label: {
                    Label("填入常见配置", systemImage: "slider.horizontal.3")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private var privacyCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("边界", systemImage: "lock.shield")
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.primaryText)

                Text("• API Key 只保存在本机钥匙串，不写进 UserDefaults，也不提交到仓库。")
                Text("• 只有你点“发送”时才会联网；不会后台同步账本。")
                Text("• 第三方接口会收到你输入的文本；敏感内容请先删掉。")
                Text("• 联网回答只作建议，不会自动写账。")
            }
            .font(theme.captionFont)
            .foregroundStyle(theme.secondaryText)
        }
    }

    private func saveKey() {
        if KeychainStore.save(apiKey) {
            keyStatus = apiKey.isEmpty ? "已清除 API Key" : "API Key 已保存到钥匙串"
        } else {
            errorMessage = "API Key 保存失败。"
        }
    }

    private func testConnection() {
        guard enabled else {
            errorMessage = "先打开“允许联网”。"
            return
        }
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请填写接口地址和模型名称。"
            return
        }

        _ = KeychainStore.save(apiKey)
        isTesting = true
        testResult = nil
        errorMessage = nil

        Task {
            do {
                let reply = try await OnlineAIClient.shared.test()
                testResult = "连接成功：\(reply.prefix(60))"
            } catch {
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }
}

// MARK: - Chat

struct OnlineAIView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme

    @AppStorage(OnlineAIConfig.enabledKey) private var enabled = false
    @AppStorage(OnlineAIConfig.modelKey) private var model = OnlineAIConfig.defaultModel

    @State private var messages: [OnlineAIMessage] = [
        OnlineAIMessage(
            role: .assistant,
            content: "我是联网记账助手。你可以问分类、预算、省钱习惯；我不会自动读取你的账本，也不会替你直接写账。"
        )
    ]
    @State private var input = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private let prompts = [
        "奶茶应该算哪类？",
        "这个月预算超了怎么办？",
        "怎么减少外卖支出？",
        "帮我解释一下结余"
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    statusCard

                    ForEach(messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }

                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("联网思考中…")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }

                    if messages.count <= 1 {
                        promptChips
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("联网 AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    OnlineAISettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("联网 AI 设置")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .alert(
            "联网 AI",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var statusCard: some View {
        LedgerCard {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((enabled ? theme.income : theme.warning).opacity(0.14))
                        .frame(width: 38, height: 38)

                    Image(systemName: enabled ? "network" : "wifi.slash")
                        .font(theme.rowIconFont)
                        .foregroundStyle(enabled ? theme.income : theme.warning)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(enabled ? "联网已开启" : "联网未开启")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(enabled ? "模型：\(model)" : "到设置里打开并填写接口")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("只发文本")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.surfaceElevated, in: Capsule())
            }
        }
    }

    private func bubble(for message: OnlineAIMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 36)
            } else {
                Image(systemName: "sparkles")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.accent)
                    .frame(width: 24, height: 24)
                    .background(theme.accent.opacity(0.12), in: Circle())
            }

            Text(message.content)
                .font(theme.bodyFont)
                .foregroundStyle(message.role == .user ? theme.onAccent : theme.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    message.role == .user ? theme.accent : theme.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            message.role == .user ? Color.clear : theme.separator.opacity(0.5),
                            lineWidth: 1
                        )
                )

            if message.role == .assistant {
                Spacer(minLength: 36)
            }
        }
    }

    private var promptChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        input = prompt
                        inputFocused = true
                    } label: {
                        Text(prompt)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("问记账、预算、分类…", text: $input, axis: .vertical)
                .focused($inputFocused)
                .font(theme.bodyFont)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(theme.headerActionFont)
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 42, height: 42)
                    .background(theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isSending ? 0.5 : 1)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, theme.pagePadding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else {
            return
        }

        input = ""
        inputFocused = false
        messages.append(OnlineAIMessage(role: .user, content: text))
        isSending = true

        Task {
            do {
                let reply = try await OnlineAIClient.shared.send(messages)
                messages.append(OnlineAIMessage(role: .assistant, content: reply))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}

#Preview("Online AI") {
    NavigationStack {
        OnlineAIView()
    }
}
