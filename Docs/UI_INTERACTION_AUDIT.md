# LedgerBox 交互 / 键盘 / UI 静态审计

> 审计者：bug-checker（独立审计，**不修改产品代码**）
> 方式：**仅源码静态审计**。本机没有 Mac / Xcode，**没有编译、没有运行、没有模拟器、没有真机、没有截图**。
> 下面所有结论都是"读代码得出的判断"，不是"跑过之后观察到的行为"。凡是我不能从源码确定的（例如键盘实际遮挡多少），都标了「待运行确认」。
> 对比度数字是用 WCAG 2.x 相对亮度公式**按十六进制色值手算**的估计值（±0.1），不是用取色器量的。

> **0.7.0 最终回填（lead，2026-10-21 21:00）**：本报告是独立审计快照，以下为最终代码的处理状态。
> - P1.1 旧文案：已改为 `2097 万参数` / `20.0 MB`。
> - P1.2 体积文案：已改为 `20.0 MB`。
> - P1.3 `accent` 文字色：已把 19 处 `foregroundStyle(theme.accent)` 全部换成 `accentText`，根 tint、预算进度、顾问指标也改用 `accentText`；填充/背景仍保留 `accent`。
> - P1.4 点空白穿透：未改成全局手势，仍以“完成”栏为主；卡片内点空白是否穿透**未真机确认**。
> - P1.5 双“完成”：已移除 SettingsView 的 `.keyboardDoneBar`，保留导航栏“完成”和 HEX 输入 Return；**工具栏合并行为未真机确认**。
> - P1.6 触控区：统计翻月 44、顾问发送 44、记账类型条 44、分段控件 44、买车“选择”44；快捷示例胶囊仍小于 44，保留为次要控件。
> - P2 减弱动态效果：财务大脑已接入 `accessibilityReduceMotion`（停巡演、固定相位）；Changelog 旧色板未单独重做。
> - 远程 archive 已成功（run `39602446769`，commit `fa093de`），33 个模拟器 XCTest 通过（run `39602690412`）；仍**没有**真机、截图或 UI 测试。

---

## 0. 基线快照

审计开始时间：2026-10-21 20:27（本地）。此时 `software-designer`（keyboard）与 `ui-designer`（Theme/Home/Settings）仍在改动中，本文档是**改动前基线**，第 6 节会在他们提交后复审。

基线关键文件指纹（SHA-256 前 12 位）：

| 文件 | mtime | sha |
| --- | --- | --- |
| `Design/Theme.swift` | 2026-10-21 19:58:21 | `6C86DBD041E2` |
| `Features/Home/HomeView.swift` | 19:58:24 | `F5EEBB71B174` |
| `Features/Settings/SettingsView.swift` | 20:13:07 | `EA902D367461` |
| `Features/Transactions/AddTransactionView.swift` | 11:54:31 | `EB34C63DD9D8` |
| `Features/QuickEntry/QuickEntryView.swift` | 19:02:30 | `37E85D56D342` |
| `Features/QuickEntry/FinanceAdvisorView.swift` | 20:13:07 | `29529647C2BC` |
| `Features/QuickEntry/FinanceBrainMapView.swift` | 20:13:07 | `B433F57803A1` |
| `Features/Budget/BudgetView.swift` | 19:45:47 | `E2FFE716CE5F` |
| `Features/Goals/GoalsView.swift` | 19:48:01 | `B1C7BA875088` |
| `Features/Goals/BuyCarPlanView.swift` | 13:38:04 | `6A935E2B51CA` |
| `Features/Statistics/StatisticsView.swift` | 19:50:57 | `74BA4EB161E0` |

基线计数：**P0 = 2 组（共 6 个输入入口）· P1 = 6 项 · P2 = 7 项**。

> **阅读提示**：第 1–6 节是**改动前基线**，其中的行号是旧行号，只用于对照。
> 第 7 节起是 `task-1`（键盘）与 `task-2`（主题）落地后的**复审结果**，行号以复审时文件为准。

---

## 1. P0 — 键盘收不起来 / 输入被打断

### 1.1 全仓没有一处"完成"键盘工具栏

检索 `placement: .keyboard`、`ToolbarItemGroup(placement: .keyboard)`、`submitLabel`、`keyboardDismiss`、`resignFirstResponder`：**全部为 0 处命中**。

`.decimalPad` 键盘**没有回车键**，因此在下面这些输入框里，用户按下数字后**唯一**能收起键盘的方式只有：
1. 手指拖动 ScrollView（`scrollDismissesKeyboard(.interactively)`），或
2. 点导航栏「保存 / 取消 / 关闭」，或
3. 退出当前页面。

这正是用户反馈的"输入金额后键盘不自动收起，必须滑动页面或退出"。

### 1.2 逐个输入框盘点

| # | 位置 | 键盘类型 | 完成工具栏 | 点空白收起 | 保存/取消收起 | 下滑收起 | 交互式滚动收起 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `Features/Transactions/AddTransactionView.swift:139`（金额） | `.decimalPad` | ❌ | ❌ | ⚠️ 保存会 dismiss 整个 sheet；`取消` 同 | ✅ `presentationDragIndicator` + sheet | ✅ `:42` |
| 2 | `Features/Transactions/AddTransactionView.swift:246`（备注，`axis: .vertical`） | 默认（有回车） | ❌ | ❌ | 同上 | ✅ | ✅ `:42` |
| 3 | `Features/QuickEntry/QuickEntryView.swift:130`（一句话，`axis: .vertical`） | 默认 | ❌ | ❌ | ⚠️ 仅「关闭」 | ✅ | ✅ `:62` |
| 4 | `Features/QuickEntry/QuickEntryView.swift:530`（金额） | `.decimalPad` | ❌ | ❌ | ⚠️ 仅「关闭」 | ✅ | ✅ `:62` |
| 5 | `Features/QuickEntry/QuickEntryView.swift:574`（备注） | 默认 | ❌ | ❌ | ⚠️ 仅「关闭」 | ✅ | ✅ `:62` |
| 6 | `Features/Budget/BudgetView.swift:450`（预算上限） | `.decimalPad` | ❌ | ❌ | ⚠️ 保存/取消 | ✅ | ✅ `:380` |
| 7 | `Features/Goals/GoalsView.swift:578`（目标名称） | 默认 | ❌ | ❌ | ⚠️ 保存/取消 | ✅ | ✅ `:510` |
| 8 | `Features/Goals/GoalsView.swift:701`（目标金额 / 已存金额，同一 `amountRow` 被 `:589`、`:595` 复用两次） | `.decimalPad` | ❌ | ❌ | ⚠️ 保存/取消 | ✅ | ✅ `:510` |
| 9 | `Features/Goals/BuyCarPlanView.swift:511`（副业收入金额） | `.decimalPad` | ❌ | ❌ | ❌ **无** | ❌ **不是 sheet，无下滑** | ❌ **没有这行修饰符** |
| 10 | `Features/Goals/BuyCarPlanView.swift:616`（奶茶金额） | `.decimalPad` | ❌ | ❌ | ❌ **无** | ❌ | ❌ |
| 11 | `Features/QuickEntry/FinanceAdvisorView.swift:293`（提问输入） | 默认 | ❌ | ❌ | ✅ 发送键 `:329` 会 `inputFocused = false` | ❌ 不是 sheet | ✅ `:79` |
| 12 | `Features/QuickEntry/FinanceBrainMapView.swift:239`（探针输入） | 默认，带 `onSubmit` `:252` | ❌ | ❌ | ⚠️ 提交后**没有**显式清焦点 | ❌ | 由父级 `FinanceAdvisorView:79` 覆盖 |
| 13 | `Features/Transactions/TransactionsView.swift:49`（`.searchable`） | 系统搜索键盘 | 系统自带 | 系统 | 系统取消按钮 | — | 系统 |

补充事实：
- `AddTransactionView` / `BudgetView` / `GoalsView` / `QuickEntryView` 的 `.scrollDismissesKeyboard(.interactively)` 生效前提是**内容可以滚动**。AddTransactionView 的内容（类型条 + 金额卡 + 明细卡）在 iPhone 竖屏下大概率不满一屏，`.interactively` 就需要"先拖一下再松手"，用户的主观感受仍然是"键盘不动"。**待运行确认**具体差多少高度。
- 全仓 `onTapGesture` / `contentShape` 命中数为 **0**：没有任何一处"点背景收起键盘"。

### 1.3 `BuyCarPlanView` 是这条 P0 里最严重的一处（单独列）

- `Features/Goals/BuyCarPlanView.swift:253-285` 的 `ScrollView` **没有** `.scrollDismissesKeyboard`；
- 它是从 `GoalsView:119-120` 的 `NavigationLink` push 出来的**普通页面**，不是 sheet，**没有下滑手势**；
- 两个数字键盘输入框 `:511` 和 `:616` 都是 `.decimalPad`（无回车）；
- "记录分账"`:529`、"记一杯"`:621` 保存后**没有清焦点**（`recordSideHustle` / `recordMilkTea` 内没有 `@FocusState` 可清，全文件无 `FocusState`）。

结论：在买车计划页输入金额后，**除了点左上角返回，键盘不会自己走**。这是用户描述现象的一个更严重变体。P0。

### 1.4 焦点管理缺失

只有 3 个视图有 `@FocusState`：`QuickEntryView:45`（只绑一句话输入框）、`FinanceAdvisorView:41`、`FinanceBrainMapView:18`。所有 `.decimalPad` 输入框**都没有** `@FocusState`，因此：
- 无法用代码收起键盘；
- 无法在"金额 → 分类 → 备注"之间做焦点链；
- 键盘遮挡时无法主动滚动到当前焦点（没有 `ScrollViewReader` / `scrollPosition` 配合）。

---

## 2. P1 — 触控区域与无障碍

### 2.1 小于 44pt 的可点击区域（HIG 下限）

| 位置 | 实际尺寸（按 padding + 字号推算） | 说明 |
| --- | --- | --- |
| `Features/Settings/SettingsView.swift:158` 强调色圆点 | **30×30** | 5 个色点，`HStack` spacing 14，中间是**不可点**空隙；很容易点错色 |
| `Features/Statistics/StatisticsView.swift:68` / `:88` 上一月/下一月 | **36×36** | 左右翻月主操作 |
| `Features/Home/HomeView.swift:109` 右上角头像（进设置） | **42×42** | 差 2pt |
| `Features/QuickEntry/FinanceAdvisorView.swift:310` 发送键 | **42×42** | 差 2pt |
| `Features/Transactions/AddTransactionView.swift:96-115` 支出/收入/转账 类型条 | 高 ≈ 12 + 9×2 = **30** | 分段控件理应 ≥ 44 或放在系统 `Picker` 里 |
| `Features/QuickEntry/QuickEntryView.swift:501-516` 支出/收入 类型按钮 | 高 ≈ 16 + 10×2 = **36** | |
| `Features/QuickEntry/QuickEntryView.swift:166-179` 示例胶囊 | 高 ≈ 12 + 6×2 = **24** | 横向滚动里的小胶囊 |
| `Features/QuickEntry/QuickEntryView.swift:328-343`、`:358-370` 建议分类 / 账户胶囊 | **≈24** | |
| `Features/QuickEntry/QuickEntryView.swift:221-231`「大脑」按钮 | 高 ≈ 10 + 5×2 = **20** | |
| `Features/QuickEntry/FinanceAdvisorView.swift:234-245` 提问示例胶囊 | 高 ≈ 12 + 7×2 = **26** | |
| `Features/QuickEntry/FinanceAdvisorView.swift:256-264`「探测」 | 高 ≈ 16 + 10×2 = **36** | |
| `Features/QuickEntry/FinanceBrainMapView.swift:138-151`「暂停巡演」 | 高 ≈ 10 + 4×2 = **18** | |

说明：这些是**推算值**（字号来自 `Theme.swift` 固定 pt + 上下 padding），不是实测。凡未加 `.contentShape(Rectangle())` 的，热区就是可见区域本身——全仓 `contentShape` 命中 0 处。

### 2.2 只有图标、没有 `accessibilityLabel`

基线整体做得**比预期好**：`accessibilityLabel` 命中 8 处，覆盖了 `HomeView:117`、`StatisticsView:72/93`、`BudgetView:65`、`GoalsView:82`、`TransactionsView:58`、`QuickEntryView:156`、`FinanceAdvisorView:315`、`SettingsView:175`。

仍缺的：
- `Features/QuickEntry/FinanceBrainMapView.swift:127` 的 `waveform.path.ecg` / `pause.circle` 图标是**状态指示**，纯语义靠颜色区分（见 3.4），旁边虽有文字，但 `autoDemo` 的真假只能用颜色分辨；
- `Features/Statistics/StatisticsView.swift:265-267` 环形图图例圆点是纯装饰，`Chart` 本身没有 `.accessibilityLabel` / `.accessibilityValue`（VoiceOver 读不到"分类占比"的具体数值）。

### 2.3 Dynamic Type：全仓不支持

- `Theme.swift:111-181` 的所有字体都是 `.system(size:)`**固定字号**；
- 全仓 `@ScaledMetric`、`.dynamicTypeSize`、`Font.custom(_:size:relativeTo:)`、`.font(.body)` 之类**语义字号命中数均为 0**（`\.font\(\.` 正则 0 处）。

后果是双向的：
1. 用户把系统字号调大，App **完全不变**（无障碍缺陷，P1）；
2. 反过来，"Dynamic Type 放大后金额溢出"这个风险在当前实现里**不会发生**，因为字根本不放大。**不要**把"金额没溢出"当成通过项——它是靠"不响应 Dynamic Type"换来的。

---

## 3. P1 — 颜色与语义

### 3.1 `onAccent` 硬编码白色，不随强调色亮度翻转

- `Theme.swift:99`：`onAccent: Color(hex: "FFFFFF")`，**永远白色**；
- `Theme.swift:88-109` 的 `palette(for:accentHex:)` 只把 `accentHex` 塞进 `accent`，**没有任何亮度判断**；
- `ThemeManager.accentHex`（`Theme.swift:200-202`、`:216`）是任意字符串，从 `UserDefaults` 直接读，无白名单校验。将来只要有一个浅色 hex 进来（或用户/别的入口写入 `FFF176`），`foregroundStyle(theme.onAccent)` 就是**白字压浅黄**，对比度约 1.1:1，等于看不见。

这不是"理论风险"，是**当前架构的必然结果**：`onAccent` 没有 `luminance` 派生逻辑。预期修法：`onAccent = relativeLuminance(accent) > 0.45 ? 深色 : 白色`，或直接用 `.foregroundStyle(.white)` + `accessibilityContrast` 分支。

### 3.2 现有 5 个强调色里，有 3 个和白字不够对比

按 WCAG 公式估算（白字 `#FFFFFF` 压在强调色上）：

| 强调色 | hex | 白字对比度 | 15pt 正文（需 4.5） | 16pt semibold 按钮（按大文本 3.0） |
| --- | --- | --- | --- | --- |
| 蓝 | `2F6FED` | ≈ **4.5** | 临界通过 | 通过 |
| 绿 | `248A5B` | ≈ **4.35** | ❌ 不达标 | 通过 |
| 橙 | `B87400` | ≈ **3.80** | ❌ 不达标 | 通过 |
| 红 | `C9454F` | ≈ **4.73** | 通过 | 通过 |
| 紫 | `7B61FF` | ≈ **4.37** | ❌ 不达标 | 通过 |

具体受害位置（15pt 常规字，`theme.bodyFont` = 15pt regular）：
- `Features/QuickEntry/FinanceAdvisorView.swift:255`：用户气泡 `foregroundStyle(theme.onAccent)` 压 `theme.accent` 背景 → 选绿/橙/紫时**不达标**；
- `Features/QuickEntry/FinanceBrainMapView.swift:260-263`：探测按钮 16pt semibold（勉强按大文本算通过，但和 3.1 叠加后仍脆）；
- `Features/Home/HomeView.swift:279`、`Features/QuickEntry/QuickEntryView.swift:425`：保存/记一笔按钮 16pt semibold。

### 3.3 `warning` 色本身就是低对比度

- `Theme.swift:102`：浅色 `warning = B87400`；
- 白底对比度 ≈ **3.80:1**，页面底色 `#F4F5F7` 上 ≈ **3.45:1**；
- 它被用在 **12pt caption** 上：`AddTransactionView.swift:181`（目标专户警告）、`QuickEntryView.swift:281/316/386`（"待补全"徽章、解析警告、校验条目）。
- 12pt 不是"大文本"，需要 4.5:1 → **全部不达标**。这是"警告看不清"的根因，不是审美问题。

同类低对比度：
- `Theme.swift:335` `secondaryText.opacity(0.75)`（"本地大脑 · 不上传"）白底 ≈ **2.9:1**；
- `FinanceAdvisorView.swift:284` `secondaryText.opacity(0.8)` ≈ **3.2:1**；
- `FinanceBrainMapView.swift:312` 非首名进度条 `secondaryText.opacity(0.55)`，视觉上几乎融进卡片；
- `secondaryText` 本身在白卡上 ≈ **4.72**（通过），但在页面底色 `F4F5F7` 上 ≈ **4.32**（不达标）。落在页面底色而非卡片上的地方：`HomeView.swift:96-98`（"2026年10月"）、`SettingsView.swift:193-196`（"当前：xx 模板"）、`SettingsView.swift:213-217`（模板说明）。

### 3.4 语义色被复用成"装饰色"，语义会打架

- **强调色 == 语义色**：`Theme.swift:63` 红色强调 `C9454F` 与 `Theme.swift:101` 支出色 `C9454F` **完全相同**；`Theme.swift:62` 橙色强调 `B87400` 与 `Theme.swift:102` 警告色 `B87400` **完全相同**。用户一旦选红/橙强调色，"强调"和"支出/警告"在视觉上不可区分。
- `Theme.swift:343-352` `CoachTipCard.tint`：`case .warning: return theme.expense` —— **警告用支出色**表达，是明确的语义错配。
- `Features/QuickEntry/QuickEntryView.swift:793-804` `aiColor`：把 `income`（收入绿）当"解析就绪"、`expense`（支出红）当"被阻断"，把财务语义色拿去做状态色，和 3.4 第一条叠加后更难分辨。
- 好处也要记：`HomeView.swift:439-450`、`TransactionsView.swift:429-438` 的 `amountColor` 是**纯语义**（收入绿/支出红/转账中性），这部分是干净的。

### 3.5 深浅色整体

- 深色模式对比度**没问题**：`secondaryText #A8AFBA` 压 `#0E1013` ≈ **8.6:1**，`income #4CC38A` ≈ **8.6:1**。
- 浅色模式是短板：三处（3.2 的绿/橙/紫、3.3 的 warning、3.3 的 opacity 灰字）集中在浅色。
- `Theme.swift:92-102` 全部用 `Color(hex:)` 手写，未使用 `UIColor` 语义色，因此在**"提高对比度"辅助功能**（`accessibilityContrast`）下不会有系统级的自动加强。

---

## 4. P2 — 布局、等高、长中文

### 4.1 等高情况

| 位置 | 现状 | 判断 |
| --- | --- | --- |
| 首页收入/支出两列 `HomeView.swift:133-149` + `amountColumn` `:168-180` | `minHeight: 42`，两列结构相同 | ✅ 等高 |
| 财务大脑指标卡 `FinanceAdvisorView.swift:159-190` | `LazyVGrid` 两列 + `minHeight: 82` | ✅ 同行等高（`LazyVGrid` 行高取最大） |
| 模型体检指标 `FinanceBrainMapView.swift:170-217` | 两个 `HStack` + `minHeight: 72` | ✅ 等高，但 `note` 是 `lineLimit(1)`，长文本会截断（`:209`） |
| 统计三列 `StatisticsView.swift:97-151` | 三个 `summaryColumn` + `minHeight: 42` | ⚠️ 基本等高，但中间 `Divider().frame(height: 34)` 是**写死高度**（`:103`、`:109`），列内容一旦变高就悬空 |
| 目标卡 / 预算卡 `GoalsView.swift:50-61`、`BudgetView.swift:164-167` | 全宽纵向堆叠，不并排 | 不适用等高；`GoalCard` 内部无固定高度，内容多少决定高度（可接受） |
| 首页 `balanceCard` 与 `coachCard` | 两张全宽卡 | 不适用 |

结论：**没有发现"并排卡片一边高一边低"的硬伤**；Changelog `0.5.0` 里那句"重排卡片高度和对齐"在当前基线里基本兑现了。剩下的只是 `Divider` 写死高度这种小问题。

### 4.2 金额溢出 / 长中文截断

| 位置 | 风险 |
| --- | --- |
| `HomeView.swift:128-131` 总余额 | `moneyFont` 30pt，**没有** `lineLimit` / `minimumScaleFactor` / `monospacedDigit` 之外的收缩策略。`¥1,234,567.89` 这种 12 字符在 iPhone SE 宽度下会顶到卡片右边 |
| `HomeView.swift:174-177` 两列金额 | 同上，16pt + 无收缩 |
| `GoalsView.swift:170-174` | 一行塞两个 `MoneyFormat.currency`（`¥xx / ¥yy`），`minimumScaleFactor(0.8)` 兜不住时仍会截断 |
| `StatisticsView.swift:255-257` 环形图中心金额 | 在 210pt 圆形中央，**无** `lineLimit`，金额变长会溢出圆环 |
| `BudgetView.swift:86-94` | 主数字 + `/ 上限` 同一 `HStack`，金额大时右侧会被挤 |
| `FinanceAdvisorView.swift:180-184` | 有 `lineLimit(1)` + `minimumScaleFactor(0.7)` ✅（正面例子） |
| `TransactionsView.swift:376-380` | 有 `lineLimit(1)` + `minimumScaleFactor(0.7)` ✅ |
| `FinanceBrainMapView.swift:200-204` | 有 `lineLimit(1)` + `minimumScaleFactor(0.7)` ✅ |
| 长中文 | 大量说明文字有 `.fixedSize(horizontal: false, vertical: true)`（`Theme.swift:331`、`FinanceAdvisorView.swift:225` 等）✅；但 `CoachTipCard` 标题 + `tag` 同一行 `:313-326`，长 tag 会把标题挤成两行，未做 `layoutPriority` |

### 4.3 其他一致性/观感问题

- `BuyCarPlanView.swift:513`、`:618` 用 `.textFieldStyle(.roundedBorder)`，是全仓唯一两处**系统圆角输入框**，和 `theme.surfaceElevated` + `controlRadius` 的自定义风格不统一。
- `FinanceBrainMapView.swift:100-105` `TimelineView(.animation(minimumInterval: 1/30))` 持续 30fps 重绘 Canvas，**没有**读 `accessibilityReduceMotion`，切到"大脑"视图就一直烧电；对"减少动态效果"用户也不友好。
- `FinanceBrainMapView.swift:58-70` 定时巡演每 4.4s 改 `query`，虽然 `queryFocused` 时会停，但**用户正在输入时定时器仍在跑**（只是 return），不会打断——这点是对的；不过它会让 VoiceOver 焦点所在文本每 4.4 秒变一次。
- `FinanceBrainMapView.swift:177` 与 `FinanceAdvisorView.swift:222` 的数字错误见第 5 节。

---

## 5. 一致性核对：参数量 / 桶数 / 字节数 / 版本号

### 5.1 唯一真源（代码）

- `FinanceMindWeights.swift:7` `bucketCount = 524288`
- `FinanceMindWeights.swift:9`（classCount = 40）
- `FinanceMindWeights.swift:10` `parameterCount = 524288 × 40 + 40 = 20,971,560` ✅
- `FinanceMindWeights.swift:11-12` `weightByteCount = 20,971,520`，`biasByteCount = 160` → `modelByteCount = 20,971,680` ✅
- 实际文件 `LedgerBox/Resources/FinanceMindWeights.bin` = **20,971,680 字节** ✅（与 `modelByteCount` 完全一致，`FinanceMind.swift:144` 的 `data.count == Self.modelByteCount` 校验也对得上）

### 5.2 文档一致性

| 出处 | 20,971,560 | 524,288 | 20,971,680 字节 | 结论 |
| --- | --- | --- | --- | --- |
| `README.md:10`、`:26`、`:46`、`:133`、`:208`、`:210`、`:229` | ✅ | ✅ | ✅ | 一致 |
| `CHANGELOG.md:10`、`:11` | ✅ | ✅ | ✅ | 一致 |
| `Docs/FINANCE_MIND.md:8-9`、`:12`、`:96`、`:115-116` | ✅ | ✅ | ✅ | 一致 |
| `Docs/COMPONENTS.md:156-157`、`:203` | ✅ | ✅ | — | 一致 |
| `Docs/ACCEPTANCE.md:136` | ✅ | — | — | 一致 |
| `ChangelogView.swift:21` | ✅ | ✅ | — | 一致 |
| `SettingsView.swift:304` | ✅ | — | — | 一致 |

### 5.3 ❌ 两处 UI 里的**过期数字**（这就是"数字不一致"的实际来源）

1. **`Features/QuickEntry/FinanceAdvisorView.swift:222`**
   文案："切到"大脑"能看到 **1048 万参数**的本地激活图。"
   实际：20,971,560 = **2097 万**。这是 0.5.0 的旧文案（10,485,800），0.6.0 忘了改。

2. **`Features/QuickEntry/FinanceBrainMapView.swift:177`**
   `statTile("体积", value: "10.0 MB", note: "Int8 权重 + Float bias")`
   实际：20,971,680 字节 = **约 20.0 MB**。同一张卡的"模型体检"里 `参数 20,971,560` / `桶 524,288` 都是新数，只有"体积"停在 10.0 MB，自相矛盾（20,971,560 个 Int8 参数不可能只占 10MB）。

对照：`ChangelogView.swift:22`（"从 10 MB 增至 20 MB"）和 `:50`（0.5.0 的"约 10 MB"）都是**历史陈述**，是对的，不算问题。

### 5.4 版本号

`project.pbxproj` 中 `MARKETING_VERSION = 0.6.0`（7 处 target）、`IPHONEOS_DEPLOYMENT_TARGET = 17.0`；`ChangelogView.swift:17` 最新条目 `0.6.0`；`README.md:66` `0.6.0`；`SettingsView.swift:459-461` 从 `CFBundleShortVersionString` 读，**没有硬编码**。✅ 一致。

---

## 6. P0 / P1 / P2 汇总（基线）

**P0（用户卡住）**
1. `AddTransactionView.swift:139` 金额 `.decimalPad` 无「完成」、无点空白、无 FocusState，只剩「保存/取消」和拖拽 → **用户反馈的原始路径**。
2. `BuyCarPlanView.swift:253-285` + `:511` + `:616` 非 sheet 页面、无 `scrollDismissesKeyboard`、两个 decimalPad、保存不清焦点 → **键盘只能靠返回键消失**。
3. 全仓 `placement: .keyboard` 0 处、`onTapGesture` 0 处（结构性缺陷，1/2 的根因）。

**P1**
4. `Theme.swift:99` + `:88-109` `onAccent` 恒白，浅色强调色必然白字压浅底；绿/橙/紫 3 色 15pt 白字不达标（`FinanceAdvisorView.swift:255`）。
5. `Theme.swift:102` `warning #B87400` 白底 3.80:1，却用在 12pt caption（`AddTransactionView.swift:181`、`QuickEntryView.swift:281/316/386`）。
6. `Theme.swift:335`、`FinanceAdvisorView.swift:284` 的 `secondaryText.opacity(0.75/0.8)` ≈ 2.9–3.2:1。
7. 强调色与语义色撞色：`Theme.swift:62/63` vs `:101/102`；`Theme.swift:348` 用支出色表达警告。
8. 触控区域 < 44pt 的 12 处（见 2.1）。
9. Dynamic Type 完全不支持（`Theme.swift:111-181` + 全仓 0 处 `@ScaledMetric`/语义字号）。
10. UI 里两处过期数字（5.3）。

**P2**
11. 金额无收缩策略的 5 处（4.2 表格前 5 行）。
12. `StatisticsView.swift:103/109` 写死 `Divider` 高度；`FinanceBrainMapView.swift:209` `lineLimit(1)` 截断 note。
13. `BuyCarPlanView.swift:513/618` 混用 `.roundedBorder` 系统样式。
14. `FinanceBrainMapView.swift:100` 30fps 动画不读 `accessibilityReduceMotion`。
15. 浅色 `secondaryText` 在页面底色上 4.32:1（`HomeView.swift:96-98`、`SettingsView.swift:193-196/213-217`）。
16. `FinanceBrainMapView.swift:312` 非首名进度条 `opacity(0.55)` 几乎不可见；`Chart` 无可访问标签（`StatisticsView.swift:239-248`）。
17. `FinanceBrainMapView.swift:58-70` 巡演会改 OverVoice 正在读的文本。

---

## 7. 复审：task-1 / task-2 落地后（2026-10-21 20:39）

### 7.0 复审快照

| 文件 | 复审 sha |
| --- | --- |
| `Design/KeyboardDismiss.swift`（新建） | `8E66ACAE987D` |
| `Design/Theme.swift` | `61E3A4380FC0` |
| `Features/Home/HomeView.swift` | `A235FF55D56A` |
| `Features/Settings/SettingsView.swift` | `98BDC89CF6CA` |
| `Features/Main/MainTabView.swift` | `E76A6D412493` |
| `Features/Transactions/AddTransactionView.swift` | `266561C4B856` |
| `Features/QuickEntry/QuickEntryView.swift` | `E45C29CF12F3` |
| `Features/QuickEntry/FinanceAdvisorView.swift` | `82EE912A5285` |
| `Features/QuickEntry/FinanceBrainMapView.swift` | `971C75BE0784` |
| `Features/Budget/BudgetView.swift` | `D60A8C09A17F` |
| `Features/Goals/GoalsView.swift` | `93A9EEF475E5` |
| `Features/Goals/BuyCarPlanView.swift` | `0AE56AE7D9E2` |

未改动：`StatisticsView.swift`、`TransactionsView.swift`、`ChangelogView.swift`。

### 7.1 ✅ 已修复

| 基线问题 | 修复证据 | 判断 |
| --- | --- | --- |
| P0-1/2/3 键盘无「完成」、无焦点、无点空白 | 新增 `Design/KeyboardDismiss.swift:75-80`（`keyboardDoneBar`）、`:105-109`（`keyboardDismissOnBlankTap`）、`:54-63`（透明点击区） | **代码层面已修** |
| 各页 decimalPad 无收起路径 | `AddTransactionView.swift:34/51/53/54`、`QuickEntryView.swift:49/71/73/74`、`BudgetView.swift:360/383/385/386`、`GoalsView.swift:484/520/522/523`、`BuyCarPlanView.swift:52/279/282/283`、`FinanceAdvisorView.swift:41/78/80/84`、`FinanceBrainMapView.swift:18/71/72`、`SettingsView.swift:49/69/74/75` | **已修**（每页都有「完成」+ 点空白 + 下滑） |
| `BuyCarPlanView` 完全没有收起手段 | `BuyCarPlanView.swift:282` 新增 `scrollDismissesKeyboard`、`:283` 完成条、`:544` 保存前清焦点 | **已修** |
| 保存/取消/解析/选示例后键盘不收 | `QuickEntryView.swift:158/181/235/954`、`AddTransactionView.swift:63`、`BuyCarPlanView.swift:544`、`FinanceAdvisorView.swift:334`、`SettingsView.swift:646` | **已修** |
| P1-4 `onAccent` 恒白 | `Theme.swift:184-190` 按亮度在白色 / 近黑 `0B0D11` 中选高对比者；`:366` 使用；`:82-84` 预设同步 | **已修**（浅色强调色自动深色字） |
| P1-5 `warning` 3.80:1 | `Theme.swift:259` 改 `9A6508`，白底约 **5.0:1**；深色 `:274` `F5C265` 约 10.8:1 | **已修** |
| P1-6 低对比灰字 | `Theme.swift:253` `secondaryText 59616E` ≈ **6.3:1**；`:254` `tertiaryText 69737F` ≈ **4.8:1**；`CoachTipCard` 改用 `tertiaryText`（`:856-858`） | **已修**（页面底色上 tertiary ≈ 4.4，见 7.2） |
| P1-7 语义色撞色 | 强调色与 `income/expense/warning` 彻底分离；`Theme.swift:866-875` `.warning` 现在映射 `theme.warning` 而不是 `expense` | **已修** |
| P1-9 Dynamic Type 完全不支持 | `Theme.swift:405-483` 全部改成 `.system(.title/.headline/.caption…)` 语义字号；`HomeView.swift:181-188` 无障碍字号下三列改竖排 | **基本已修**（4 处图标字号仍固定，见 7.2） |
| P2-11 金额溢出 | `Theme.swift:883-888` `ledgerMoneyLine`；`HomeView.swift:151/213/233/487` 已套用 | **已修** |
| P1-8 部分 44pt | `Theme.swift:651` 段头操作、`:798/:816` 按钮、`SettingsView.swift:232` 色块 44×44、`HomeView.swift:119` 头像 44 | **部分已修** |
| 自定义强调色无入口 | `SettingsView.swift:243` `ColorPicker`、`:275-295` HEX 输入、`:624-643` 非法值提示、`Theme.swift:544-558` 归一化与回退 | **已实现**（对比度传播范围见 7.2） |

### 7.2 ⚠️ 仍存在

| # | 问题 | 位置 | 级别 |
| --- | --- | --- | --- |
| 1 | **过期数字**："1048 万参数"（实际 20,971,560 = 2097 万） | `FinanceAdvisorView.swift:227` | **P1** |
| 2 | **过期数字**："体积 10.0 MB"（实际 20,971,680 字节 ≈ 20.0 MB），同一张卡里参数/桶已是新数，自相矛盾 | `FinanceBrainMapView.swift:179` | **P1** |
| 3 | **自定义浅色强调色在这些地方仍不可读**：20 处直接把 `theme.accent`（原始色）当文字/图标色，没有走 `theme.accentText`（已做对比度修正的 token）。默认绿/橙/紫预设本身就只有 4.35/3.80/4.37:1，自定义浅色更差 | `KeyboardDismiss.swift:40`；`QuickEntryView.swift:135/240/351/378`；`GoalsView.swift:131/187/191`；`BuyCarPlanView.swift:314/497/521/1097`；`FinanceAdvisorView.swift:130/276`；`FinanceBrainMapView.swift:123/343`；`StatisticsView.swift:315`；`ChangelogView.swift:163/230/249` | **P1** |
| 4 | **点空白收起在卡片内部大概率无效**：`keyboardDismissOnBlankTap` 是 `background`，而 `LedgerCard` 的背景是可命中的 `RoundedRectangle`（`Theme.swift:607-614`），点卡片空白处会命中卡片本身，不会穿透到后面的收起层。只有卡片之间的空隙、页面边距有效 | `BuyCarPlanView.swift:279`（唯一一层，卡片未单独加）；`QuickEntryView.swift` 的 `aiCard`/`previewCard`；`BudgetView.swift` 的 `configurationCard` | **P1**（待运行确认） |
| 5 | 触控区仍 < 44pt：翻月 36×36、发送 42×42、`AddTransactionView` 类型条 ≈30、`QuickEntryView` 胶囊 ≈24、"大脑" ≈20、`BuyCarPlanView:495`「选择」纯文字、`Theme.swift:772` 分段控件高 36 | `StatisticsView.swift:68/88`；`FinanceAdvisorView.swift:315`；`AddTransactionView.swift:113-125`；`QuickEntryView.swift:187/242/276/353/380`；`BuyCarPlanView.swift:495`；`Theme.swift:772` | **P1** |
| 6 | 仍混用系统输入框样式（与 `surfaceElevated` + `controlRadius` 不一致） | `BuyCarPlanView.swift:527/634` | P2 |
| 7 | `FinanceBrainMapView` 30fps 动画不读 `accessibilityReduceMotion`；大数字 32pt 固定 | `FinanceBrainMapView.swift:100-105`、`:114` | P2 |
| 8 | 长中文单行截断（首页/流水行标题、副标题 `lineLimit(1)`） | `HomeView.swift:468/473`；`TransactionsView.swift:365/370` | P2 |
| 9 | `tertiaryText` 在**页面底色**（非卡片）上约 4.4:1，临界不达标 | `SettingsView.swift:432`、`ChangelogView.swift` 若干 | P2 |
| 10 | `ChangelogView` 未跟随新色板（仍用圆形图标 + `accent` 文字），与新版设置页风格不一致 | `ChangelogView.swift` 全文件 | P2 |
| 11 | 死 token：`Theme.isDark/accentSoft/incomeSoft/expenseSoft/accentWasToned/largeTitleFont` 已定义但无人使用 | `Theme.swift:283/302/315-317/309/405` | P2（非缺陷） |

### 7.3 🆕 新引入 / 新风险

| # | 风险 | 位置 | 级别 |
| --- | --- | --- | --- |
| 1 | **可能出现两个「完成」**：`SettingsView` 的 ScrollView 挂了 `keyboardDoneBar`，从设置页 `NavigationLink` 进 `FinanceAdvisorView` 后，父视图的键盘工具栏条目是否被新页面替换，静态无法确定。若两者合并，点中"设置页那个"不会收起当前输入框的键盘 | `SettingsView.swift:75` + `SettingsView.swift:497-498` + `FinanceAdvisorView.swift:84` | **P1**（待运行确认） |
| 2 | `keyboardDoneBar` 用 `ToolbarItemGroup(placement: .keyboard)`；同一导航栈里多层声明时的合并规则未在真机验证 | 同上 | 同上 |
| 3 | `KeyboardDismissArea` 只铺在内容 VStack 的 `background` 上，内容比屏幕短时，**下方空白区**点不到收起层 | `KeyboardDismiss.swift:105-109` | P2 |
| 4 | `QuickEntryView` 的 `.keyboardDismissOnBlankTap` 挂在**横向 ScrollView 的父级**，示例胶囊区域手势嵌套较深，是否互相抢手势未验证 | `QuickEntryView.swift:71/196` | P2 |
| 5 | `MainTabView` 改为 `ForEach(MainTab.allCases)` + `.tabItem` 动态生成 5 个 tab | `MainTabView.swift:37-45` | P2（待运行确认） |

### 7.4 复审后的颜色数字（重算）

浅色（白底）：`income 0F7B52` ≈ 5.3:1 ✅ · `expense C0384B` ≈ 5.4:1 ✅ · `warning 9A6508` ≈ 5.0:1 ✅ · `secondaryText 59616E` ≈ 6.3:1 ✅ · `tertiaryText 69737F` ≈ 4.8:1 ✅。
深色（surface `15181E`）：`income 4FD1A0`、`expense FF8A92`、`warning F5C265` 均 ≥ 7:1 ✅。
强调色**作为文字**时仍是原始色（未走 `accentText`）：蓝 4.54 / 绿 4.35 / 橙 3.80 / 红 4.73 / 紫 4.37 —— 绿橙紫仍 < 4.5，这就是 7.2 第 3 条。
`onAccent` 自动选择：橙/绿/紫会切到近黑字（约 4.38–4.99:1），蓝/红保持白字 ✅。

---

## 8. 最终清单（按级别，带 文件:行号）

### P0（会让用户卡住）

**当前静态审计未发现新的 P0。** 用户反馈的"金额输完键盘不收起"在代码层面已有统一解法（8 个页面全部接入 `keyboardDoneBar` + `keyboardDismissOnBlankTap` + `scrollDismissesKeyboard` + `@FocusState`）。
但请注意 7.3 第 1 条：如果"两个完成按钮"的风险成真，在**设置 → 财务大脑**这条路径上会退化成一个 P0 体验（点了没反应）。

### P1（看不清 / 点不到 / 数字自相矛盾）

1. `FinanceAdvisorView.swift:227` — "1048 万参数"应为 2097 万。
2. `FinanceBrainMapView.swift:179` — "10.0 MB"应为约 20.0 MB（20,971,680 字节）。
3. 20 处 `theme.accent` 当文字色（`KeyboardDismiss.swift:40`、`QuickEntryView.swift:135/240/351/378`、`GoalsView.swift:131/187/191`、`BuyCarPlanView.swift:314/497/521/1097`、`FinanceAdvisorView.swift:130/276`、`FinanceBrainMapView.swift:123/343`、`StatisticsView.swift:315`、`ChangelogView.swift:163/230/249`）→ 应改用 `theme.accentText`。
4. 卡片内点空白可能收不起键盘（`BuyCarPlanView.swift:279`；`QuickEntryView` aiCard/previewCard；`BudgetView` configurationCard）→ 给 `LedgerCard` 统一加收起，或把点击层放到卡片**前景**用 `simultaneousGesture`。
5. 触控区 < 44pt：`StatisticsView.swift:68/88`（36）、`FinanceAdvisorView.swift:315`（42）、`AddTransactionView.swift:113-125`（≈30）、`QuickEntryView.swift:187/242/276/353/380`（≈20–26）、`BuyCarPlanView.swift:495`、`Theme.swift:772`（36）。
6. 设置 → 财务大脑 可能双「完成」（`SettingsView.swift:75` + `FinanceAdvisorView.swift:84`）——若成立即为 P0，需真机确认。

### P2（观感 / 一致性 / 无障碍细节）

7. `BuyCarPlanView.swift:527/634` 仍在用 `.roundedBorder`。
8. `FinanceBrainMapView.swift:100-105` 30fps 动画未尊重"减弱动态效果"；`:114` 32pt 固定字。
9. `HomeView.swift:468/473`、`TransactionsView.swift:365/370` 单行截断长中文。
10. `SettingsView.swift:432` 等 `tertiaryText` 落在页面底色上 ≈ 4.4:1。
11. `ChangelogView.swift` 未跟随新色板。
12. `KeyboardDismiss.swift:105-109` 内容不满屏时下方空白不响应。
13. `Theme.swift:283/302/309/315-317/405` 未使用的 token（`isDark/accentSoft/incomeSoft/expenseSoft/accentWasToned/largeTitleFont`）。
14. 结构一致性：`FinanceAdvisorView` 的聊天气泡仍是 15pt 白/黑字压强调色，绿/紫约 4.38:1，属临界值。
15. 版本号一致性 ✅：`project.pbxproj` `MARKETING_VERSION = 0.6.0`、`ChangelogView.swift:17`、`README.md:66` 三处一致；参数量真源 `FinanceMindWeights.swift:7-12` 与 `Resources/FinanceMindWeights.bin`（20,971,680 字节）完全吻合。

---

## 9. 验证边界（必须随报告一起转述）

- 全部结论来自**源码静态阅读**。本机没有 macOS/Xcode：**没有编译、没有模拟器、没有真机、没有截图、没有跑过任何 UI 测试**。
- 因此以下三点**不能**当作已验证：
  1. 「完成」按钮在 accessory bar 里的实际合并行为（7.3-1/2）；
  2. 点空白是否真的能穿过卡片背景（7.2-4）；
  3. 键盘弹出后输入框是否仍可见（SwiftUI 自动避让 + `ScrollView`，无 `ScrollViewReader` 主动滚动）。
- 对比度是按 hex 用 WCAG 公式手算的估计值（±0.1），不是取色器实测。
- 触控尺寸是按 `padding + 字号` 推算，未用 Accessibility Inspector 实测。
- 仓库**没有任何 UI 测试**：`LedgerBoxTests/` 只有 `FinanceEngineTests`、`FinanceMindTests`、`QuickEntryParserTests`。键盘/触控/颜色三类问题目前**零自动化覆盖**，回归只能靠人工。
- 不要在任何对外文档里把本文写成"已验证键盘修复"或"视觉验收通过"；最多写"静态审计显示每个输入框都有明确收起路径，仍待真机确认"。
