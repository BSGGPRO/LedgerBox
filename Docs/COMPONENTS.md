# LedgerBox 组件与架构

本文描述当前源码的分层、关键类型、数据流和扩展点。GitHub Actions 已成功 archive，33 个 XCTest 已在 iPhone 16 / iOS 26.2 模拟器通过；但本文不代表真机运行、签名安装或人工 UI 验收。

---

## 1. 总览

```text
LedgerBoxApp
└── RootView
    ├── MainTabView
    │   ├── HomeView
    │   │   ├── QuickEntryView (sheet)
    │   │   └── AddTransactionView (sheet)
    │   ├── TransactionsView
    │   │   └── AddTransactionView (sheet)
    │   ├── StatisticsView
    │   ├── BudgetView
    │   └── GoalsView
    │       └── BuyCarPlanView (NavigationLink)
    └── SettingsView (sheet)
        ├── ChangelogView (NavigationLink)
        └── Beausoleil Bilibili (Link)

LedgerBoxWidgetBundle
└── LedgerBoxWidget (systemSmall / systemMedium)
```

设计目标：

1. **通用引擎稳定**：收支、转账、退款、预算、统计、目标倒计时不依赖场景。
2. **场景规则可插拔**：日常、学生、买车模板只提供种子与规则，不污染 `FinanceEngine`。
3. **写入边界单一**：所有余额变更经过 `LedgerService`。
4. **视觉集中**：颜色、字体、圆角、间距集中在 `Theme`。
5. **本地优先**：完全离线、无登录、无云同步；0.4.0 起已删除联网 AI。

---

## 2. 分层

### 2.1 App 层

| 文件 | 职责 |
|---|---|
| `LedgerBox/App/LedgerBoxApp.swift` | `@main` 入口；注入 `PersistenceController.shared` 的 `viewContext`；创建 `ThemeManager`；`RootView` 应用主题与颜色模式 |

`RootView` 负责：

- 读取 `@Environment(\.colorScheme)`
- 调用 `themeManager.theme(for:)`
- 注入 `\.ledgerTheme`
- 设置 `.tint`
- 设置 `.preferredColorScheme`

### 2.2 Persistence 层

| 文件 | 职责 |
|---|---|
| `LedgerBox/Persistence/PersistenceController.swift` | `NSPersistentContainer`；`shared` 持久化容器；`preview` 内存容器与种子数据 |

关键点：

- `shouldAddStoreAsynchronously = false`，启动时同步加载。
- 加载失败使用 `assertionFailure`（Debug），避免静默进入半初始化状态。
- 预览容器使用 `NSInMemoryStoreType`，不写真实 SQLite。
- 预览种子：现金账户、默认分类、4 笔交易、2 个预算、2 个目标。

### 2.3 Models 层

| 文件 | 职责 |
|---|---|
| `LedgerBox/Models/ManagedObjects.swift` | 手写 `NSManagedObject` 子类；Decimal 桥接；`fetchRequest()`；`TransactionProviding` 实现 |

实体：

| Entity | Swift 类 | 说明 |
|---|---|---|
| `Account` | `Account` | 账户余额、类型、币种、排序、锁定 |
| `Transaction` | `LedgerTransaction` | 交易；实体名保持 `Transaction`，Swift 类改名避免与 `SwiftUI.Transaction` 冲突 |
| `Category` | `Category` | 收入/支出分类；软删除 |
| `Budget` | `Budget` | 总预算/分类预算、月/周、启停用 |
| `SavingsGoal` | `SavingsGoal` | 目标金额、当前金额、优先级、状态、倒计时 |
| `TemplateRules` | `TemplateRules` | 模板类型、配置 JSON、启用状态 |
| `AppSettings` | `AppSettings` | 主题、强调色、激活模板、副业比例 |

当前 **不使用 Core Data relationship**，实体之间通过 UUID 外键关联。这样可以减少删除规则与迁移风险，但需要调用方自行保证引用完整性。

### 2.4 Finance 层

| 文件 | 职责 |
|---|---|
| `LedgerBox/Finance/FinanceEngine.swift` | 纯 Foundation 财务投影：汇总、区间、预算进度、目标倒计时、月度序列、日累计净额、分类支出 |
| `LedgerBox/Finance/LedgerService.swift` | 唯一交易写入边界；单笔/批量创建、余额影响、删除回滚 |
| `LedgerBox/Finance/TemplateRules.swift` | `TemplateRuleProviding` 协议；日常/学生/买车模板计划；买车规则函数 |
| `LedgerBox/Finance/TemplateInstaller.swift` | 将模板计划 upsert 到 Core Data；保留历史数据 |
| `LedgerBox/Finance/CSVExporter.swift` | CSV 字符串生成与 `FileDocument` |
| `LedgerBox/Finance/FinanceEngine.swift` | `Decimal.rounded`、`doubleValue`、`MoneyFormat` |

`FinanceEngine` 明确不 import Core Data / SwiftUI。它只依赖 `TransactionProviding`：

```swift
protocol TransactionProviding {
    var financeType: TransactionType { get }
    var financeCategoryID: UUID? { get }
    var financeAccountID: UUID { get }
    var financeAmount: Decimal { get }
    var financeDate: Date { get }
}
```

`LedgerTransaction` 通过扩展实现该协议。

### 2.5 Design 层

| 文件 | 职责 |
|---|---|
| `LedgerBox/Design/Theme.swift` | `ThemeMode`、`ThemeAccent`、`Theme`、`ThemeManager`、`LedgerThemeKey`、`LedgerCard`、`LedgerSectionHeader`、`Color(hex:)` |

`Theme` 是值类型，包含：

- 颜色令牌
- 卡片/页面/间距
- 字号令牌
- 控制圆角、分段圆角、图标圆尺寸

`ThemeManager` 是 `ObservableObject`，持久化：

- `ledgerbox.theme.mode`
- `ledgerbox.theme.accentHex`

`EnvironmentKey` 为 `\.ledgerTheme`，页面通过 `@Environment(\.ledgerTheme)` 读取。

### 2.6 Features 层

| 目录 | 页面 | 说明 |
|---|---|---|
| `Features/Home` | `HomeView` | 总余额、本月汇总、最近 5 笔、空状态、记一笔、设置 |
| `Features/Transactions` | `TransactionsView`、`AddTransactionView` | 流水筛选/搜索/删除；新增收入/支出/转账/退款 |
| `Features/Statistics` | `StatisticsView` | 6 个月柱状图、分类环图、累计趋势 |
| `Features/Budget` | `BudgetView`、`BudgetEditorView` | 总/分类预算、月/周、启停用、空状态 |
| `Features/Goals` | `GoalsView`、`GoalEditorView`、`BuyCarPlanView` | 目标进度/倒计时；买车场景 |
| `Features/Settings` | `SettingsView`、`ChangelogView` | 主题、模板、CSV、更新日志、作者入口 |
| `LedgerBoxWidget` | `LedgerBoxWidget`、`LedgerBoxWidgetBundle` | WidgetKit 源码保留；默认不嵌入 App，避免自签失败 |
| `Features/Main` | `MainTabView` | 五 Tab 容器 |
| `Features/QuickEntry` | `QuickEntryParser`、`QuickEntryAI`、`MoneyBrain`、`FinanceMind`、`FinanceAdvisorView`、`FinanceBrainMapView`、`QuickEntryView` | 一句话解析、本地文本小 AI、5,643 参数金钱分类器、10,485,800 参数财务意图模型、大脑可视化 |

### 2.7 QuickEntry 层

| 文件 | 职责 |
|---|---|
| `QuickEntryParser.swift` | 纯 Foundation + NaturalLanguage；把“微信买奶茶 15 元”解析为金额、收支、分类、账户、物品、备注；跳过 `M5200`/`2台` 等型号与数量；不依赖 SwiftUI/Core Data |
| `QuickEntryAI.swift` | 本地解释层；输出状态、字段完整度、缺失字段和示例；不调用模型/网络 |
| `MoneyBrain.swift` | 5,643 参数多项逻辑回归；字符 n-gram 哈希；输出语义类别与置信度 |
| `MoneyBrainWeights.swift` | 由 `Tools/train_money_brain.py` 生成的 Int16 量化权重 |
| `FinanceMind.swift` | 10,485,800 参数财务意图分类器 + 账本快照 + 固定规则回答；不生成数字、不写账、不联网 |
| `FinanceMindWeights.swift` | 模型元数据：40 意图 × 262,144 桶 + 40 bias，scale 48；大权重在 `Resources/FinanceMindWeights.bin` |
| `FinanceAdvisorView.swift` | 财务大脑页；“对话 / 大脑”分段；本月收支/结余/余额、预算/目标快照、财务问答和提示胶囊 |
| `FinanceBrainMapView.swift` | 本地模型可视化：持续动画的意图激活图、4.4 秒自动巡演、模型体检、实时探针、延迟与 40 类覆盖 |
| `QuickEntryView.swift` | AI 记账面板；示例胶囊、小 AI 状态卡、金钱小模型提示、财务大脑入口、分类/账户建议；不请求麦克风 |

边界：

- Parser 只接收 `CategoryOption` / `AccountOption` 快照，不直接持有 `NSManagedObject`。
- 小 AI 只做本地规则解释和字段完整度，不生成不存在的金额/分类。
- MoneyBrain 只给建议排序/提示，不覆盖解析器明确结果；置信度低于 0.42 不显示。
- FinanceMind 只做 40 类财务/会计意图路由；回答数字来自本机 Core Data，不由模型生成，不自动写账。
- FinanceMind 不是 Qwen2.5-0.5B 裁层，不是生成式模型；合成训练集准确率不代表真实准确率。
- 已取消 Siri、快捷指令和 App Intents；没有系统自动化写账入口。
- 0.4.0 起已删除联网 AI、Keychain 和 URLSession；App 不发起网络请求。

---

## 3. 数据流

### 3.1 新增交易

```text
AddTransactionView
  → 解析金额为 Decimal
  → 校验账户/分类/日期
  → LedgerService.record(...)
      → LedgerDraft
      → recordBatch([draft])
          → validate 全部草稿
          → 创建 LedgerTransaction
          → applyBalanceImpact
          → context.save()
  → @FetchRequest 刷新首页/流水/统计/预算
```

### 3.1.1 极速记账 / 财务大脑

```text
QuickEntryView
  → QuickEntryParser.parse(text, categories, accounts)
  → 展示金额/收支/分类/账户/物品/备注与价格软提醒
  → 未匹配字段由用户选择
  → LedgerService.record(...)
  → 首页 @FetchRequest 刷新

FinanceAdvisorView（对话）
  → FinanceMind.predict(text)（40 意图，10,485,800 参数）
  → FinanceSnapshot（本机账本/预算/目标）
  → FinanceAdvisor.answer（固定模板 + Decimal）

FinanceAdvisorView（大脑）
  → FinanceMind.probe(text, limit: 8)
  → FinanceBrainProbe（top 意图/置信度/特征数/延迟）
  → FinanceBrainMapView（Canvas 呼吸/旋转/流动脉冲 + 自动巡演 + 探针列表）
```

### 3.2 批量分账

```text
BuyCarPlanView
  → BuyCarTemplateRules.splitSideHustle
  → BuyCarTemplateRules.allocateSurplus
  → [LedgerDraft]
  → LedgerService.recordBatch
      → 全部校验
      → 全部创建
      → 一次 save
      → 失败 rollback
```

批量写入用于：

- 副业收入 70/30 分账
- 结余结转（修机/买车/备用金）
- 未来可能的多账户拆单

### 3.3 删除交易

```text
TransactionsView
  → 确认删除
  → LedgerService.delete(transaction)
      → 按类型反向调整账户余额
      → 转账同时反向调整转入账户
      → context.delete(transaction)
      → context.save()
```

### 3.4 预算进度

```text
BudgetView
  → FinanceEngine.interval(for: period, containing: Date())
  → FinanceEngine.spending(categoryID:transactions:in:)
  → FinanceEngine.budgetProgress(limit:spent:)
  → ProgressView / 超预算提示
```

### 3.5 统计

```text
StatisticsView
  → FinanceEngine.monthlySeries(endingAt:count:6)
  → 近 6 个月收入/支出柱状图
  → FinanceEngine.spending(...) 按分类聚合
  → 分类占比环图
  → FinanceEngine.dailyCumulativeNet(...)
  → 本月累计结余折线/面积图
```

金额始终是 `Decimal`；只有在 Charts 的 `BarMark`/`LineMark`/`SectorMark` 参数边界转换为 `Double`。

### 3.6 目标倒计时

```text
GoalsView
  → FinanceEngine.savingsCountdown(target:current:transactions:)
      → 最近 30 天窗口
      → 有效天数 = 有非转账交易的去重自然日
      → 有效天数 < 7：累积中
      → 日均净结余 <= 0：无法估算
      → 否则 ceil(剩余金额 / 日均净结余)
```

### 3.7 模板应用

```text
SettingsView
  → 二次确认
  → TemplateInstaller.apply(rules, in: context)
      → upsert 分类
      → upsert 预算
      → upsert 目标（按 templateTag）
      → upsert 专户（按名称）
      → 旧模板 active=false
      → 新模板 active=true
      → AppSettings.activeTemplateId
      → context.save()
```

模板应用不会删除交易，不会重置账户余额，不会重置已有目标当前金额。

### 3.8 CSV 导出

```text
SettingsView
  → CSVExporter.makeCSV(...)
  → CSVDocument
  → .fileExporter
  → 用户选择保存位置
```

CSV 字段：

```text
日期,类型,金额,分类,账户,转入账户,备注,模板标签
```

使用 UTF-8 BOM，便于 Windows Excel 读取中文。

---

## 4. 关键类型

| 类型 | 位置 | 说明 |
|---|---|---|
| `ThemeMode` | `Theme.swift` | system/light/dark |
| `ThemeAccent` | `Theme.swift` | 蓝/绿/橙/红/紫 |
| `Theme` | `Theme.swift` | 颜色、字号、圆角、间距 |
| `ThemeManager` | `Theme.swift` | 主题持久化 |
| `AccountType` | `FinanceEngine.swift` | cash/savings/goal/reserve |
| `TransactionType` | `FinanceEngine.swift` | income/expense/transfer/refund |
| `CategoryKind` | `FinanceEngine.swift` | expense/income |
| `BudgetPeriod` | `FinanceEngine.swift` | monthly/weekly |
| `SavingsGoalStatus` | `FinanceEngine.swift` | active/achieved/frozen |
| `TemplateKind` | `FinanceEngine.swift` | daily/student/car/custom |
| `LedgerSummary` | `FinanceEngine.swift` | income/expense/net |
| `BudgetProgress` | `FinanceEngine.swift` | limit/spent/remaining/ratio/isOverBudget |
| `GoalCountdown` | `FinanceEngine.swift` | status/remainingAmount |
| `LedgerDraft` | `LedgerService.swift` | 批量写入草稿 |
| `TemplatePlan` | `TemplateRules.swift` | 分类/预算/目标/账户/提示 |
| `TemplateInstaller` | `TemplateInstaller.swift` | 模板 upsert |
| `CSVDocument` | `CSVExporter.swift` | 文件导出文档 |
| `QuickEntryParser.ParsedEntry` | `QuickEntryParser.swift` | 一句话解析快照与问题列表 |
| `QuickEntryAI.Insight` | `AIAssistant.swift` | 小 AI 状态、完整度、缺失字段 |
| `MoneyBrainPrediction` | `MoneyBrain.swift` | 语义类别、置信度、建议收支类型 |
| `FinanceBrainProbe` | `FinanceMind.swift` | top 意图、置信度、特征数、哈希桶、参数量、推理延迟 |
| `FinanceCoach` | `FinanceEngine.swift` | 首页/目标/预算/统计/对话共用的本地今日提示；只写句子，不写账 |

---

## 5. 并发与生命周期

- 普通 UI 写入使用主 `viewContext`：极速记账面板、模板安装、批量分账、删除交易。
- 已取消 App Intents；没有后台自动化写账路径，所有写入仍经过 `LedgerService`。
- 金额落库前统一调用 `roundedToCents()`，只保留两位小数；不使用会默认取整的 `Decimal.rounded()`。
- `PersistenceController` 同步加载 store。
- 未使用 CloudKit、网络或第三方 SDK。
- `@FetchRequest` 负责页面数据刷新。
- 预览使用内存容器，不污染真实数据。

如果未来引入后台写入，必须：

1. 使用独立 context，不能把主线程的 `Account`/`Category` 对象传进去。
2. 在 context 的 `perform` 内读取、校验、写入。
3. 显式设置合并策略（当前为 `NSMergeByPropertyObjectTrumpMergePolicy`）。
4. 只通过 `LedgerService` 改余额。
5. 不把 `NSManagedObject` 跨线程/跨 context 传递。

---

## 6. 扩展点

### 新增场景模板

1. 在 `TemplateRules.swift` 新建 `XxxTemplateRules: TemplateRuleProviding`。
2. 提供 `TemplatePlan`。
3. 在 `TemplateCatalog.allKinds` 与 `TemplateCatalog.all` 注册。
4. 如需要专属页面，新建 `Features/.../XxxView.swift`，只组合通用引擎与模板规则。
5. 不要把场景逻辑写进 `FinanceEngine`。

### 新增交易类型

1. 修改 `TransactionType`。
2. 更新 `FinanceEngine.summary` / `spending`。
3. 更新 `LedgerService.applyBalanceImpact` 与 `delete` 的反向逻辑。
4. 更新 `AddTransactionView`、`TransactionsView` 筛选。
5. 更新 CSV 类型输出。
6. 更新 16 条边界文档与测试。

### 新增主题令牌

1. 在 `Theme` 增加字段。
2. 在 `Theme.palette(for:accentHex:)` 提供浅色/深色值。
3. 在页面通过 `theme.xxx` 使用。
4. 不在页面写死 hex。

### 新增 CSV 字段

1. 修改 `CSVExporter` 表头与行。
2. 保持字段转义：双引号包裹，内部双引号翻倍。
3. 保持 UTF-8 BOM。
4. 不加入任何凭据、设备标识、真实个人信息。

---

## 7. 已知结构缺口

- 无 `SavingsGoal.accountId`，买车目标与专户通过 `templateTag` + 名称同步。
- 无账户管理 UI、无分类管理 UI。
- 无周期记账页面；“补记本期”尚未接入。
- `AppSettings.themeMode` 与 `ThemeManager` 未双向同步。
- 测试 Target 已运行：33 个测试在 iPhone 16 / iOS 26.2 模拟器通过（run `39596723535`）。
- AppIcon 与 Asset Catalog 已随 GitHub Actions archive 编译；未做真机视觉检查。
- 已通过 GitHub Actions `macos-15` 归档（run `39596549161`）；未在本地 Xcode 运行，也未做真机验证。
- iOS 不能读取其他 App 的通知内容；已取消快捷指令/Siri，没有系统自动化写账入口。
- 本地小 AI 是规则 + 5,643 参数金钱分类器 + 10,485,800 参数财务意图模型；财务大脑未做真实账本准确率测试，也未做真机视觉验收；0.4.0 起不含联网 AI。

---

## 8. 文件地图

```text
LedgerBox/
  App/LedgerBoxApp.swift
  Models/ManagedObjects.swift
  Persistence/PersistenceController.swift
  Design/Theme.swift
  Finance/
    FinanceEngine.swift
    LedgerService.swift
    TemplateRules.swift
    TemplateInstaller.swift
    CSVExporter.swift
  Features/
    Home/HomeView.swift
    Transactions/AddTransactionView.swift
    Transactions/TransactionsView.swift
    Statistics/StatisticsView.swift
    Budget/BudgetView.swift
    Goals/GoalsView.swift
    Goals/BuyCarPlanView.swift
    QuickEntry/AIAssistant.swift
    QuickEntry/MoneyBrain.swift
    QuickEntry/MoneyBrainWeights.swift
    QuickEntry/QuickEntryParser.swift
    QuickEntry/QuickEntryView.swift
    Settings/SettingsView.swift
    Settings/ChangelogView.swift
    QuickEntry/FinanceBrainMapView.swift
    Main/MainTabView.swift
  LedgerBoxWidget/
    LedgerBoxWidgetBundle.swift
    LedgerBoxWidget.swift
    Info.plist
  Resources/
    LedgerBox.xcdatamodeld/
      .xccurrentversion
      LedgerBox.xcdatamodel/contents
    Assets.xcassets/
      Contents.json
      AppIcon.appiconset/Contents.json
      AppIcon.appiconset/AppIcon-1024.png
.github/workflows/ios-unsigned.yml
LedgerBoxTests/
  FinanceEngineTests.swift
```

---

## 9. 相关文档

- [`FINANCE_RULES.md`](FINANCE_RULES.md)
- [`BUILD_STEPS.md`](BUILD_STEPS.md)
- [`WINDOWS_BUILD_SIGN.md`](WINDOWS_BUILD_SIGN.md)
- [`ACCEPTANCE.md`](ACCEPTANCE.md)
- [`THEMING.md`](THEMING.md)
- [`../README.md`](../README.md)
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
