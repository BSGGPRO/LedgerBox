# LedgerBox

LedgerBox 是一个面向 iOS 17+ 的本地优先通用记账本，使用 SwiftUI + Core Data 构建。项目把“通用记账引擎”和“场景模板规则”分开：前者只负责收支、转账、退款、预算、统计和目标进度；后者只提供日常、学生、买车三套可选配置。

作者：**Beausoleil** · [Bilibili 个人空间](https://space.bilibili.com/1477283849)

> **当前状态**  
> 静态源码与文档已完成；GitHub Actions `macos-15` 已成功归档未签名 IPA（run `39569024041`，commit `7815cc5`），版本 `0.2.0`，包含小 AI 文本记账、更新日志和作者入口；已移除语音权限，默认不嵌入 Widget，方便自签。测试尚未运行，IPA 未签名，需要你用自己的证书自签；尚未做真机运行验证。

---

## 功能

- **首页**：总余额、本月收入/支出/结余、最近 5 笔流水、空状态、记一笔入口、设置入口。
- **流水**：全部交易、收入/支出/转账/退款/全部筛选、按日分组、备注/分类/账户/类型搜索、滑动删除并回滚余额。
- **新增交易**：收入、支出、转账、退款；金额、账户、转入账户、分类、日期、备注。
- **统计**：近 6 个月收支柱状图、分类支出占比环图、本月累计结余折线/面积图、月份切换。
- **预算**：总预算/分类预算、月/周周期、进度、超预算提示、新增/编辑/删除、启停用。
- **目标**：储蓄目标、进度环、30 天平均净结余倒计时、达成/冻结状态、新增/编辑/删除。
- **设置**：浅色/深色/跟随系统、五种强调色、模板应用、CSV 本地导出、隐私说明、更新日志。
- **小 AI 文本记账**：首页“极速”入口；输入“微信买奶茶 15 元”，本地拆出金额/收支/分类/账户/备注；显示字段完整度、示例胶囊、分类建议和常用账户建议；不联网、不上传文本。
- **快捷指令 / Siri**：`AddTransactionIntent` 结构化记账；`QuickAddIntent` 接收分享文本、短信/邮件内容或个人自动化输入；只有字段无歧义时才自动保存，否则返回确认提示。iOS 不允许读取其他 App 的通知。
- **小组件源码**：保留 WidgetKit 小 / 中尺寸源码；当前默认不嵌入 App，避免 `PlugIns` 嵌套签名导致自签安装失败。需要时可在 Xcode 中重新加入 Embed 阶段。
- **作者入口**：设置页可打开 Beausoleil 的 Bilibili 个人空间。
- **买车场景**：修机 4,400 → 买车 25,000 优先级、打卡 100、固定工资 500、年度补贴、副业 70/30 分账、本月现金结余结转、奶茶 150/月与 2 杯/周告警、目标专户支出/转出提醒。

---

## 技术栈

| 层 | 技术 |
|---|---|
| UI | SwiftUI，iOS 17.0+ |
| 图表 | Apple Charts（`BarMark` / `SectorMark` / `LineMark` / `AreaMark`） |
| 持久化 | Core Data，`NSPersistentContainer`，本地 SQLite |
| 金额 | `Decimal` + `NSDecimalNumber` 持久化桥接 |
| 主题 | 自定义 `Theme`、`ThemeManager`、`EnvironmentKey` |
| 小 AI | 本地规则 + Apple `NaturalLanguage`；无模型、无网络 |
| 自动化 | App Intents / App Shortcuts（快捷指令、Siri） |
| 图标 | SF Symbols |
| 依赖 | 无 CocoaPods、无第三方 SPM 包 |

---

## 环境要求

- macOS 14 或更高版本（建议）
- Xcode 15 或更高版本
- iOS 17.0 模拟器或真机
- Swift 5.9 编译器；工程 `SWIFT_VERSION = 5.0` 语言模式

工程信息：

- Target：`LedgerBox`
- Bundle ID：`com.example.ledgerbox`
- Marketing Version：`0.2.0`
- Deployment Target：`17.0`
- 设备族：iPhone + iPad
- 无 `DEVELOPMENT_TEAM`、无证书、无描述文件

---

## 快速开始

1. 在 macOS 上打开 `LedgerBox.xcodeproj`。
2. 选择 `LedgerBox` scheme。
3. 选择任意 iOS 17 模拟器。
4. 点击 Run。
5. 首次启动会自动创建 `现金账户` 和默认收支分类。

模拟器运行不需要开发者账号。真机运行需要你在本地 Xcode 中选择自己的 Team；**不要把 Team ID、证书或描述文件提交到仓库**。

首次启动没有交易，首页会显示空状态。点击“记一笔”记录第一笔收入或支出；点击“极速”进入小 AI 文本记账，输入一句话即可解析，不需要麦克风或语音权限。

工程包含 `LedgerBoxTests` Target，可在 Mac 上通过 `Cmd+U` 或 `xcodebuild test` 运行；当前尚未实际执行。

---

## 无签名构建

Windows 无法直接编译 SwiftUI。可选路径：

1. **GitHub Actions macOS runner**：在云端 macOS 上执行 `xcodebuild archive`，设置 `CODE_SIGNING_ALLOWED=NO`，产出未签名 `.app` / `.ipa` 工件。
2. **远程 Mac**：通过 SSH 或远程桌面在 Mac 上构建。
3. **借用 Mac**：本地 Xcode 构建。

详见：

- [`Docs/WINDOWS_BUILD_SIGN.md`](Docs/WINDOWS_BUILD_SIGN.md)
- [`Docs/BUILD_STEPS.md`](Docs/BUILD_STEPS.md)

本项目不提供：

- 已签名/可直接安装的 IPA；仓库里的旧版未签名 IPA 只作历史产物
- `.p12`、`.mobileprovision`、Team ID
- 证书生成、证书托管、签名自动化
- App Store 上架保证

---

## 目录结构

```text
LedgerBox.xcodeproj/                 Xcode 工程与共享 scheme
LedgerBox/
  App/                               App 入口与 RootView
  Models/                            NSManagedObject 子类与 Decimal 辅助
  Persistence/                       NSPersistentContainer、预览种子数据
  Design/                            Theme、ThemeManager、卡片、环境键
  Finance/                           FinanceEngine、LedgerService、CSV、模板
  Features/
    Home/                            首页
    Transactions/                    流水列表、新增交易
    Statistics/                      统计图表
    Budget/                          预算
    Goals/                           储蓄目标、买车场景
    Settings/                        设置、模板、CSV
    Main/                            五 Tab 容器
    QuickEntry/                      一句话解析、小 AI 文本助手、App Intents
  Resources/
    LedgerBox.xcdatamodeld/          Core Data 模型
    Assets.xcassets/                 AppIcon 占位
LedgerBoxTests/                      XCTest：财务规则、买车规则、极速记账解析
.github/workflows/                   无签名 iOS 归档工作流
Docs/                                架构、规则、构建、签名、验收、主题文档
README.md
LICENSE
CONTRIBUTING.md
.gitignore
```

---

## 核心设计

### 通用引擎与场景模板分离

- `FinanceEngine` 只依赖 `TransactionProviding` 协议和 Foundation，不依赖 Core Data、SwiftUI 或任何场景规则。
- `LedgerService` 是唯一的交易写入与账户余额变更边界。
- `TemplateRules` / `TemplateInstaller` 只负责场景配置与种子数据，不进入通用统计公式。
- `BuyCarPlanView` 只组合通用引擎与买车规则，不修改 `FinanceEngine`。

### 金额

- 所有金额字段使用 Core Data `Decimal`。
- Swift 领域计算使用 `Decimal`。
- `Double` 只出现在 UI 比例、进度条、图表和天数取整边界。
- 不使用 `Double` 存储金额。

### 本地优先

- 无登录、无账号、无云同步、无网络请求、无广告、无内购。
- 数据只写入本机 Core Data SQLite。
- CSV 只通过系统文件导出器保存到用户选择的位置。

### 小 AI 文本记账

- `QuickEntryParser` 只依赖 Foundation + `NaturalLanguage`，不依赖 UI/Core Data。
- 解析“微信买奶茶 15 元”得到金额、分类、账户与备注；无法唯一匹配时要求手动补全，不静默猜测。
- `QuickEntryAI` 只做本地解释、字段完整度、示例和建议，不调用云端模型；输入文本不会离开设备。
- 已移除语音识别、麦克风和语音识别权限；App 不再请求麦克风。
- App Intents 回到 `MainActor` 使用 `viewContext` 串行写入，仍经过 `LedgerService` 的金额、日期、账户与余额校验。
- 快捷指令只有字段无歧义时才自动保存；否则返回需确认信息，避免误记账。

---

## 财务规则摘要

- 删除交易时先回滚账户余额，再删除记录。
- 转账只生成一条 Transfer 记录，不计入收入/支出。
- 退款冲减对应分类支出，不产生负数金额。
- 预算只约束支出；周预算使用 ISO 周一到周日。
- 分类软删除，历史交易保留；统计中归入“其他”。
- 记账日期不能晚于当前时间。
- 储蓄目标达成后停止倒计时，不自动分配资金。
- 买车优先级：修机 4,400 → 买车 25,000 → 备用金。
- 副业收入至少 70% 进目标账户，最多 30% 进备用金。

完整 16 条边界与公式见 [`Docs/FINANCE_RULES.md`](Docs/FINANCE_RULES.md)。

---

## 已知限制

- 未实际编译、未运行测试、未签名。
- 已有 `Assets.xcassets` 与本地生成的 1024×1024 AppIcon 占位；未在 Xcode 中验证 Asset Catalog 编译，也未做上架截图/视觉审查。
- 已加入 `.github/workflows/ios-unsigned.yml`；尚未在 GitHub Actions 实际运行。
- 无账户管理 UI、无分类管理 UI；默认账户与分类由 Persistence 种子和模板创建。
- 无周期记账 UI；需求中的“补记本期”尚未接入页面。
- `SavingsGoal` 与 `Account` 没有 Core Data 关系或 `accountId` 外键；买车页通过 `templateTag` + 专户名称同步。
- 买车页的目标当前金额以专户余额为准，手动编辑目标金额后会在下次进入买车页时被同步覆盖。
- 本月结余只允许结转一次；结转后又新增收入，不能再次结转。
- `AppSettings.themeMode` / `accentColorHex` 字段存在，但当前主题实际由 `ThemeManager` + UserDefaults 驱动，两者未双向同步。
- 无多币种换算；`currencyCode` 默认 CNY，v1 只按 CNY 展示。
- 已有 `LedgerBoxTests` Target，共 20 个测试，覆盖财务汇总、退款、预算进度、副业分账、结余优先级、金额分位存储与 11 个极速记账解析用例；尚未实际运行。
- iOS 不允许读取其他 App 的通知内容；快捷指令只能处理分享文本、短信/邮件、个人自动化等系统允许的输入，不能监听银行/微信通知。
- 小 AI 是本地规则 + 字段完整度，不是生成式大模型；没有云端推理，也不会“猜”不存在的账。
- 新版未签名 IPA 已由 GitHub Actions 生成：`LedgerBox-unsigned-0.2.0-AI.ipa`，728,341 字节，SHA-256 `037083DC3A666BF508CCFB9C20CA9ABE2518495189E9B2E0EE5DB486DC1C289A`；无 `PlugIns`、无麦克风/语音权限，需自签后安装。
- 当前默认是单 target：不再嵌入 `PlugIns/LedgerBoxWidget.appex`，所以 `lcsign` 只需签主 App。Widget 源码仍在仓库中，但不会进入 IPA。
- 如果要重新启用小组件，必须在 Xcode 中恢复 Embed 阶段，并同时签主 App 与 appex；否则会出现图标有、点不开的安装失败。

---

## 文档

- [`Docs/COMPONENTS.md`](Docs/COMPONENTS.md)：架构、文件地图、数据流、扩展点
- [`Docs/FINANCE_RULES.md`](Docs/FINANCE_RULES.md)：16 条边界、公式、模板规则
- [`Docs/BUILD_STEPS.md`](Docs/BUILD_STEPS.md)：Xcode 构建、运行、常见错误
- [`Docs/WINDOWS_BUILD_SIGN.md`](Docs/WINDOWS_BUILD_SIGN.md)：Windows 限制、macOS 无签名构建、自签边界
- [`Docs/ACCEPTANCE.md`](Docs/ACCEPTANCE.md)：P0/P1/P5 验收清单、静态证据、已知缺口
- [`Docs/THEMING.md`](Docs/THEMING.md)：主题令牌、明暗配色、扩展方式
- [`Docs/GITHUB_RESEARCH.md`](Docs/GITHUB_RESEARCH.md)：开源 iOS 记账项目调研与可借鉴项
- [`Docs/OPEN_SOURCE_10.md`](Docs/OPEN_SOURCE_10.md)：10 个开源记账项目的许可证与取舍
- [`CHANGELOG.md`](CHANGELOG.md)：面向用户的版本更新记录
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：贡献流程与硬规则

---

## 许可证

MIT License，见 [`LICENSE`](LICENSE)。

---

## 免责声明

本项目是记账工具源码，不构成财务、税务或投资建议。使用前请自行备份数据，并在自己的 Mac 上完成编译、测试和签名验证。
