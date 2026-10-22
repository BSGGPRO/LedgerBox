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
            version: "0.12.1",
            dateText: "2026.10.22",
            title: "财务大脑单页对话",
            changes: [
                "“财务大脑”改为单页闭环：设置入口直接进入对话页，不再经过核心路由/Qwen 的二级跳转页。",
                "核心路由卡片改为内联展示；右侧“对话”按钮只聚焦底部输入框，不跳页、不显示箭头。",
                "本地解释引擎改为纯状态卡片，显示“已加载/未就绪”徽标，不可点击。",
                "对话记录、快捷提问和固定输入栏保留在同一页；快捷气泡只填充输入框并自动聚焦，发送按钮改为 paperplane.fill。",
                "新消息追加后自动滚动到对话底部，键盘弹起时输入栏随安全区上移。"
            ]
        ),
        ChangelogEntry(
            version: "0.12.0",
            dateText: "2026.10.22",
            title: "原生导航、聊天输入与 AI 日志诊断",
            changes: [
                "首页移除胶囊顶栏，改用原生大标题 NavigationStack；月份副标题位于标题下方，头像移入右上角 toolbar。",
                "图片记账弹窗移除胶囊顶栏，改用标准 Modal 导航栏和右上角系统 xmark。",
                "财务大脑新增固定底部输入栏：加号上传图片、圆角输入框、发送按钮；建议气泡改为填充输入框并自动聚焦。",
                "设置 AI 区合并为“财务大脑”单一入口，详情页分别展示 40 个核心路由意图和 Qwen 本地解释引擎状态。",
                "新增“AI 财务日志诊断”：提取最近 30 天流水，生成结构化文本，由本机 Qwen 输出三个 Markdown 诊断段落；只读，不写账。"
            ]
        ),
        ChangelogEntry(
            version: "0.11.1",
            dateText: "2026.10.22",
            title: "浅色主题收口与 0.5B 真实自检",
            changes: [
                "浅色/白色主题的浮动标题、底栏、记账气泡、账户页和图片页关闭按钮改用主题表面色，不再固定成深色块。",
                "财务大脑的“Qwen 0.5B 本地解释层”显示真实加载状态、完成/拒绝计数和最近一次真实输出。",
                "新增“运行一次真实解释”自检：用固定示例调用 llama.cpp，只显示通过数字白名单校验的输出；模拟器明确提示不加载。",
                "设置 AI 区显示 0.5B 状态与真实调用计数，点按可进入财务大脑运行自检。",
                "解释层仍然只改写确定性结果，不写账、不改金额、不补日期。"
            ]
        ),
        ChangelogEntry(
            version: "0.11.0",
            dateText: "2026.10.22",
            title: "多账单、JSON 备份与 AI 动作",
            changes: [
                "一张图可拆成多笔账单：按 OCR 行距切分，无法识别的块合并到邻近账单，最多 20 笔。",
                "多账单先逐笔核对金额、日期、分类和账户，可排除重复项；确认后整批写入，撤销会删除整批并恢复余额。",
                "设置新增 JSON 全量备份与恢复，覆盖账户、分类、流水、预算、目标、模板和设置；导入前完整校验，失败回滚。",
                "财务大脑新增动作路由：记一笔、查账、导出 CSV、导出 JSON、图片记账；写账和导出都要先点确认，成功后可撤销。",
                "新增本地诊断日志，只记录事件和计数，不记录金额、商户、问题原文、截图或订单号。",
                "0.5B 解释层增加生成中保护和手动卸载路径，解释长度上限 96 token。"
            ]
        ),
        ChangelogEntry(
            version: "0.10.0",
            dateText: "2026.10.21",
            title: "内置 Qwen2.5-0.5B 本地解释层",
            changes: [
                "安装包内置 Qwen2.5-0.5B-Instruct Q4_K_M，约 491 MB，离线可加载。",
                "内置 llama.cpp b11796 iOS 运行时；模拟器不加载，真机从 Frameworks 动态加载。",
                "财务大脑新增“0.5B 本地解释”：只改写已算好的 Decimal 结果，不参与金额、比例、日期计算。",
                "解释文本中的数字必须出现在原结果中，否则整段丢弃并回退到确定性文案。",
                "模型加载失败、内存不足或运行时缺失时，所有旧功能继续可用。"
            ]
        ),
        ChangelogEntry(
            version: "0.9.4",
            dateText: "2026.10.21",
            title: "去掉设置和目标的返回按钮",
            changes: [
                "不再把设置作为 TabView 的第六个页面；TabView 固定五个页面，避免 iOS 自动生成 More 列表。",
                "目标页不再出现“返回 / More”导航按钮。",
                "设置改为独立页面覆盖层，进入后齿轮高亮，其它 Tab 不再同时高亮。",
                "设置页仍然是页面切换，不是 sheet 抽屉。"
            ]
        ),
        ChangelogEntry(
            version: "0.9.3",
            dateText: "2026.10.21",
            title: "设置改成页面，记账选项变气泡",
            changes: [
                "设置不再以 sheet 抽屉弹出，改为底栏第七个页面；切换后底栏保持可见，不再盖住当前页面。",
                "中间加号图标从 16pt 提到 22pt，仍与其它项同宽同高，不凸出、不缩小。",
                "极速记账与记一笔改为两个很小的气泡，带小尾巴，点加号后依次向上弹出。",
                "点任一气泡立即收起并进入对应记账流程；切换 Tab 会自动收起。"
            ]
        ),
        ChangelogEntry(
            version: "0.9.2",
            dateText: "2026.10.21",
            title: "底栏七等分，头像回右上",
            changes: [
                "本地头像回到首页右上角的玻璃顶栏，不再放在底部。",
                "底栏改为七等分：首页、流水、统计、+、预算、目标、设置；加号在正中，设置在最右。",
                "加号、设置与五个 Tab 使用相同尺寸、字号和高度，不再单独放大、凸出或缩小。",
                "点按加号弹出系统记账方式选择：极速记账或手动记一笔，不再展开自绘大按钮。"
            ]
        ),
        ChangelogEntry(
            version: "0.9.1",
            dateText: "2026.10.21",
            title: "加号回到 TabBar 中间",
            changes: [
                "把 + 从独立悬浮行移进底部 TabBar，与“首页 / 流水 / 统计”在同一行，固定在屏幕正中。",
                "同一行为本地头像（左角）、首页、流水、+、统计、预算、目标、设置（右角）；不再使用悬浮胶囊操作行。",
                "原生 TabBar 隐藏，改为本地自绘栏；选中态用白色高亮，未选中态降为 56% 白色，深色背景下仍可读。",
                "展开菜单的两个动作向上展开并向左对齐，避免在小屏上越过右边界。"
            ]
        ),
        ChangelogEntry(
            version: "0.9.0",
            dateText: "2026.10.21",
            title: "算力翻倍，数字交给精算引擎",
            changes: [
                "FinanceMind 从 20,971,560 参数扩到 41,943,080 参数：40 类意图 × 1,048,576 个哈希桶 + 40 个 bias；Int8 权重约 40 MB，仍完全本地。",
                "新增 AI 计算路由：模型只选择支出、分类占比、预算、账户余额、结余、结余率、应急金、目标进度、现金流九类公式；所有数字由 Decimal 精确计算，模型不生成金额。",
                "财务大脑回答会显示“模型路由/规则兜底”、计算类型和可复制的算式，便于核对；没有数据时明确说没有，不编数字。",
                "移除顶部头像栏和微信/支付宝第三方入口；头像改为底部左侧，本地资料，不上传。",
                "底部悬浮操作行：左侧本地头像、中间加号（极速记账/记一笔）、右侧设置，位置更符合单手操作。"
            ]
        ),
        ChangelogEntry(
            version: "0.8.0",
            dateText: "2026.10.21",
            title: "拍账单，先核对再入账",
            changes: [
                "新增图片记账：相册/相机截图 → Vision 本机 OCR → 本地正则提取金额与时间 → 本地模型/商户词库分类 → 草稿预览 → 用户确认后写入。",
                "订单号只保存 SHA-256 哈希；重复订单或同一分钟同商户同金额会在写入前拦截；确认后提供 6 秒“撤销”，逐条删除并恢复余额。",
                "转账/提现支持手续费两种口径：从本金扣除或另付；手续费单独记一笔支出，撤销时一起回滚。",
                "新增本地商户词库（瑞幸、星巴克、滴滴、美团等 20+ 商户），支持繁体/全角归一化、别名、Levenshtein 与 bigram 相似度；模型低置信度时返回“其他/需核对”，不硬猜。",
                "首页改为悬浮胶囊毛玻璃顶栏：UltraThinMaterial + rgba(20,20,22,0.72) + 1px 描边，滚动 8pt 后 200ms 收缩；不使用系统导航栏灰条。",
                "右上角头像改为本地资料入口：昵称、头像、来源、隐私说明；设置移入该菜单，仍可 sheet 打开。微信/支付宝需要 AppID/SDK/服务端，未配置时明确禁用，不伪造授权。",
                "全局 FAB 合并“⚡ 极速记账（图片/相机）”和“📝 记一笔（手动）”，移除首页底部双按钮；FAB 为 62pt 胶囊主按钮，展开两个 46pt 动作。",
                "新增 19 个图片解析/词库/去重/写入撤销 XCTest；总测试 52 个。"
            ]
        ),
        ChangelogEntry(
            version: "0.7.0",
            dateText: "2026.10.21",
            title: "键盘会收，颜色会看",
            changes: [
                "所有输入框增加键盘“完成”栏：金额数字键盘、备注多行输入、预算/目标/买车副业、财务大脑探针都能直接收起键盘，不用再上下滑动或退出页面。",
                "点卡片外空白、保存、取消、下滑也会收起键盘；切换账户/分类/日期后自动收起，数字键盘不再必须退出页面。",
                "重做首页和设置页视觉：20pt 圆角、20pt 卡片内边距、8pt 间距、胶囊按钮、细分隔线；首页只保留右上角一个用户图标进设置。",
                "重做配色：浅色/深色双层表面、可读的收入/支出/警告色；强调色不再一律白字，浅色强调色自动改用深色文字。",
                "设置页新增自定义强调色：5 个预设、ColorPicker、HEX 输入、实时预览和对比度提示；非法颜色会回退或提示，不再静默变灰。",
                "金额、目标、预算、统计等卡片统一等高和单行缩放，减少一边高一边低；大字号下本月三列自动改为竖排。",
                "财务大脑仍为 20,971,560 参数、524,288 哈希桶；这次没有改模型数字。"
            ]
        ),
        ChangelogEntry(
            version: "0.6.0",
            dateText: "2026.10.21",
            title: "两千万参数档",
            changes: [
                "财务大脑从 10,485,800 参数升到 20,971,560 参数：40 类意图 × 524,288 个字符 n-gram 哈希桶 + 40 个 bias。",
                "权重文件从 10 MB 增至 20 MB，仍为 Int8 量化、本机映射读取，不上传、不联网。",
                "参数量翻倍主要降低哈希碰撞、提高稀疏特征区分度；它不是生成式大模型，合成验证集分数不能当成真实准确率。",
                "同步更新财务大脑页、模型体检、设置页和测试中的参数量与哈希桶数。"
            ]
        ),
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
                        .foregroundStyle(theme.accentText)
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
                            .foregroundStyle(theme.accentText)
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
                                .foregroundStyle(theme.accentText)

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
