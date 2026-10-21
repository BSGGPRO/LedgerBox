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
            version: "0.5.0",
            dateText: "2026.10.21",
            title: "会动的财务大脑",
            changes: [
                "财务大脑激活图改为持续动画：呼吸核心、旋转节点、流动脉冲，不用输入也会动。",
                "新增自动巡演：每 4.4 秒切换现金流、预算、报销、折旧、应收、增值税、房贷等问题，点“暂停巡演”可停。",
                "新增本地财务教练：首页、目标、预算、统计、财务大脑都会根据本机账本给出今日提示，不编数字、不自动写账。",
                "目标页新增完成时间预测：按近 30 天净结余估算剩余天数、约几个月和预计日期。",
                "训练语料加入 50/30/20、零基预算、信封预算、债务雪球/雪崩、会计科目表、直线法折旧、先进先出等公共模板短语。",
                "设置页新增 GitHub 开源地址；首页右上角改为单个用户图标，点进去就是设置，去掉与底部重复的加号。",
                "重排卡片高度和对齐，减少两列卡片一边高一边低。"
            ]
        ),
        ChangelogEntry(
            version: "0.4.0",
            dateText: "2026.10.22",
            title: "千万参数本地财务大脑",
            changes: [
                "彻底移除联网 AI、接口配置、API Key 和钥匙串依赖；App 不再包含任何网络请求代码。",
                "财务大脑升级为 10,485,800 参数：40 类记账意图 × 262,144 个字符 n-gram 哈希桶，另加 40 个 bias。",
                "新增现金流、对账、发票、报销、工资、存货、折旧、摊销、增值税、权责发生、备用金、应收应付、借款、房贷、房租、水电、医疗、教育、公益等意图。",
                "财务大脑页新增“大脑”视图：意图激活图、模型体检、实时探针、延迟和前 6 个概率。",
                "Int8 权重放在 FinanceMindWeights.bin，约 10 MB；推理仍在本机 CPU 完成，不上传账本。",
                "合成语料训练，合成验证集仅用于回归自测，不代表真实世界准确率；真实语句仍需你自己考。"
            ]
        ),
        ChangelogEntry(
            version: "0.3.1",
            dateText: "2026.10.21",
            title: "物品与金额识别",
            changes: [
                "新增物品识别：从“买了一台电动车”提取电动车，从“这个物品是口红”提取口红。",
                "新增型号/数量过滤：M5200、9号、2台、3杯等不再被误当成金额。",
                "新增价格软提醒：口红 1000 元这类高于常见区间的支出会提示核对小票，但不阻止保存。",
                "支持“价格/售价/标价/实付”等支出线索，减少“发现”被误判为收入关键词的问题。"
            ]
        ),
        ChangelogEntry(
            version: "0.3.0",
            dateText: "2026.10.21",
            title: "财务专用小模型",
            changes: [
                "新增 15,380 参数财务意图模型：20 个财务意图 × 768 个字符 n-gram 桶。",
                "新增财务大脑页：本月收入/支出/结余/余额、预算、目标、分类、储蓄、负债、保险、税务等问答。",
                "回答由本地账本快照和固定规则生成，不编数字，不自动写账，不联网。",
                "它不是 Qwen 裁层，也不是生成式大模型；训练数据是合成财务短语，真实准确率仍需测试。"
            ]
        ),
        ChangelogEntry(
            version: "0.2.2",
            dateText: "2026.10.21",
            title: "联网 AI 实验（0.4.0 已移除）",
            changes: [
                "历史版本曾提供可选联网 AI；0.4.0 已彻底删除该功能及全部网络代码。",
                "历史版本曾把 API Key 存在钥匙串；0.4.0 已移除钥匙串依赖，不再保存任何密钥。",
                "取消 Siri、快捷指令和 App Intents，删除 NSSiriUsageDescription，不再暴露系统快捷指令入口。",
                "AI 记账卡重做：渐变图标、联网入口、金钱小模型胶囊；新增联网问答页和聊天气泡。",
                "设置新增 AI 分区：开关、接口、模型、密钥、连接测试和隐私边界说明。",
                "联网回答只作建议，不自动写账；账本解析仍由本地小 AI 完成。"
            ]
        ),
        ChangelogEntry(
            version: "0.2.1",
            dateText: "2026.10.21",
            title: "塞进一个金钱小模型",
            changes: [
                "新增 5,643 参数的本地金钱小模型，识别餐饮/交通/购物/住房/娱乐/医疗/工资/理财/转账/退款等语义。",
                "小模型只做分类提示和建议排序，不覆盖解析器明确结果，不生成金额。",
                "卡片新增“金钱小模型 · 餐饮 84%”提示。",
                "它不是 0.5B/1B 大语言模型；训练数据是合成短语，真实准确率仍需测试。"
            ]
        ),
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
