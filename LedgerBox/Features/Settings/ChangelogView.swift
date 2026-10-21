import SwiftUI

// Add a new entry at the top for every user-visible release. Keep the wording
// factual: what changed, not a promise that it has been verified on device.
struct ChangelogEntry: Identifiable {
    let version: String
    let dateText: String
    let title: String
    let changes: [String]

    var id: String { version }
}

enum ChangelogCatalog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "0.2.0",
            dateText: "2026.10.21",
            title: "小 AI 来了，语音退场",
            changes: [
                "新增本地文本小 AI：输入一句话，拆出金额、收支、分类和账户；不联网、不上传文本。",
                "新增字段完整度、示例胶囊、分类建议和常用账户建议，补全更快。",
                "移除语音识别、麦克风与语音识别权限，减少权限弹窗和自签变量。",
                "重做 AI 记账页：小 AI 状态卡、识别结果卡、补全信息卡分层展示。",
                "UI 参考 GitHub 开源记账项目的卡片/胶囊布局，未复制代码。",
                "保留快捷指令 / Siri；WidgetKit 源码保留，但当前默认不嵌入 App，避免自签失败。"
            ]
        ),
        ChangelogEntry(
            version: "0.1.0",
            dateText: "2026.10.21",
            title: "目标更清楚，记账更快",
            changes: [
                "新增极速记账：一句话识别金额、收支、分类和账户；有歧义时先让你确认。",
                "新增本地语音输入：优先使用设备端中文识别，不支持时回到键盘，不上传音频。",
                "新增快捷指令 / Siri：支持结构化记一笔，也支持用一段文本记一笔。",
                "新增原生 WidgetKit 小组件（小 / 中），可放在主屏幕快速打开 LedgerBox。",
                "设置页新增作者 Beausoleil 的 Bilibili 个人空间入口。",
                "修复部分页面把金额取整到元的问题，金额统一保留两位小数。",
                "修复手动选择分类、账户或收支类型后，继续输入会被自动识别改回去的问题。",
                "优化目标、预算、买车计划和模板分账的金额一致性。"
            ]
        )
    ]
}

struct ChangelogView: View {
    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing) {
                header
                timeline
                footer
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("更新日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var header: some View {
        LedgerCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                        .fill(theme.surfaceElevated)
                        .frame(width: 44, height: 44)

                    Image(systemName: "clock.arrow.circlepath")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.accent)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("每一次改动，都写在这里")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Text("只记录用户能感知的变化；不把内部重构写成版本亮点。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            LedgerSectionHeader(title: "版本记录")

            ForEach(ChangelogCatalog.entries) { entry in
                let isCurrent = entry.id == ChangelogCatalog.entries.first?.id
                let isLast = entry.id == ChangelogCatalog.entries.last?.id

                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(isCurrent ? theme.accent : theme.separator)
                            .frame(width: 9, height: 9)
                            .overlay {
                                Circle()
                                    .stroke(theme.background, lineWidth: 2)
                            }
                            .padding(.top, 19)

                        if !isLast {
                            Rectangle()
                                .fill(theme.separator)
                                .frame(width: 1, height: 52)
                        }
                    }
                    .frame(width: 9)

                    entryCard(entry, isCurrent: isCurrent)
                }
            }
        }
    }

    private func entryCard(_ entry: ChangelogEntry, isCurrent: Bool) -> some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("v\(entry.version)")
                        .font(theme.rowMoneyFont)
                        .foregroundStyle(theme.primaryText)

                    Text(entry.dateText)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Spacer(minLength: theme.smallSpacing)

                    if isCurrent {
                        Text("当前版本")
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                theme.accent.opacity(0.12),
                                in: Capsule()
                            )
                    }
                }

                Text(entry.title)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entry.changes, id: \.self) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("·")
                                .font(theme.bodyFont.weight(.bold))
                                .foregroundStyle(theme.accent)

                            Text(change)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text("由 Beausoleil 维护。更新日志随版本发布更新；未签名 IPA 或本地构建版本，不在此处标注为“已验证”。")
            .font(theme.captionFont)
            .foregroundStyle(theme.secondaryText.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

#Preview("更新日志 · 浅色") {
    NavigationStack {
        ChangelogView()
    }
    .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("更新日志 · 深色") {
    NavigationStack {
        ChangelogView()
    }
    .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
