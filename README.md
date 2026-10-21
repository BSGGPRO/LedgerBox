# LedgerBox

LedgerBox 是一个面向 iOS 17+ 的本地优先通用记账本，使用 SwiftUI + Core Data 构建。项目把“通用记账引擎”和“场景模板规则”分开：前者只负责收支、转账、退款、预算、统计和目标进度；后者只提供日常、学生、买车三套可选配置。

作者：**Beausoleil** · [Bilibili 个人空间](https://space.bilibili.com/1477283849)

开源地址：**[github.com/BSGGPRO/LedgerBox](https://github.com/BSGGPRO/LedgerBox)**

> **当前状态**  
> 0.9.3 源码已完成。GitHub Actions `macos-15` 待归档；57 个 XCTest 待重跑。尚未做真机安装、截图级视觉验收或真实账本准确率测试；IPA 未签名，需要你用自己的证书自签。

---

## 功能

- **首页**：总余额、本月收入/支出/结余、今日本地提示、最近 5 笔流水、空状态；顶部只保留标题，不再放头像。
- **图片记账**：相册/相机截图 → Vision 本机 OCR → 正则提取金额/时间/订单号 → 本地模型/商户词库分类 → 草稿预览 → 用户确认后写入；订单号只存 SHA-256，重复单在写前拦截，成功后 6 秒可撤销。
- **悬浮玻璃顶栏**：UltraThinMaterial + `rgba(20,20,22,0.72)` + 1px 描边，滚动 8pt 后 200ms 收缩；不使用系统导航栏灰条。
- **底栏七等分**：首页、流水、统计、+、预算、目标、设置；加号居中并略大 1 档，设置最右；设置是页面而不是抽屉；头像在首页右上角玻璃顶栏。
- **本地资料**：昵称、头像、隐私说明；微信/支付宝第三方入口已从界面删除，只保留本地资料，不伪造授权。
- **流水**：全部交易、收入/支出/转账/退款/全部筛选、按日分组、备注/分类/账户/类型搜索、滑动删除并回滚余额。
- **新增交易**：收入、支出、转账、退款；金额、账户、转入账户、分类、日期、备注。
- **统计**：近 6 个月收支柱状图、分类支出占比环图、本月累计结余折线/面积图、月份切换。
- **预算**：总预算/分类预算、月/周周期、进度、超预算提示、新增/编辑/删除、启停用。
- **目标**：储蓄目标、进度环、近 30 天净结余倒计时、预计完成月份/日期、达成/冻结状态、新增/编辑/删除。
- **设置**：浅色/深色/跟随系统、五种强调色、模板应用、CSV 本地导出、隐私说明、更新日志、GitHub 开源地址。
- **小 AI 文本记账**：首页“极速”入口；输入“微信买奶茶 15 元”，本地拆出金额/收支/分类/账户/物品/备注；会跳过 `M5200`、`9号`、`2台` 等型号和数量，不把它们当金额。
- **物品与价格识别**：“我买了一台电动车，9号M5200花费22000”提取物品“电动车”、金额 22000、支出；“这个物品是口红，但是口红价格是1000元”提取“口红”、1000、支出，并给出价格偏高软提醒。
- **金钱小模型**：5,643 参数，字符 n-gram + 逻辑回归，给餐饮/交通/购物/工资/理财等语义排序；只做提示，不覆盖解析器结果。
- **本地财务大脑**：**41,943,080 参数**，40 个财务/会计意图，1,048,576 个字符 1–3 gram 哈希桶；模型只选公式，金额、占比、账户余额、预算、结余率、应急金、目标进度、现金流全部交给 Decimal 精算引擎，模型不生成数字。
- **AI 计算路由**：财务大脑把可计算问题路由到 9 类闭集公式，回答卡显示“模型路由/规则兜底”、计算类型和可复制算式；没有数据时明确说没有，不编数字。
- **大脑可视化**：财务大脑页顶部“对话 / 大脑”切换；大脑页包含持续动画的意图激活图（呼吸核心、旋转节点、流动脉冲）、4.4 秒自动巡演、模型体检、实时探针、top 6 概率、特征数、推理延迟和 40 类覆盖。
- **本地财务教练**：首页、目标、预算、统计、财务大脑共享本机账本快照，给出预算预警、支出超收入、目标临门一脚、分类集中和“今天先别急着下单”等提示；不编数字、不自动写账。
- **键盘收得起**：所有金额/备注/预算/目标/探针输入都加了键盘“完成”栏；切换账户/分类/日期、保存/取消、下滑也会清焦点。另有点卡片外空白收起路径；卡片内部能否穿透需真机确认。
- **自定义强调色**：5 个预设 + ColorPicker + HEX 输入；浅色强调色自动用深色字，文字色按对比度校正，非法颜色回退并提示。
- **首页/设置重排**：20pt 圆角、8pt 间距、胶囊按钮、细分隔线；卡片等高，金额单行缩放，大字号下本月三列改竖排。
- **完全离线**：0.4.0 起已删除联网 AI、API Key、Keychain 和全部网络请求；账本与输入文本都不离开设备。
- **已取消 Siri**：删除 App Intents / 快捷指令入口和 `NSSiriUsageDescription`，不再暴露 Siri 记账。
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
| 小 AI | 本地规则 + `NaturalLanguage` + 5,643 参数金钱分类器 + 41,943,080 参数财务意图模型 + Decimal 精算路由 |
| 权重 | Int8 二进制资源，`Data` 映射读取；无 Core ML、无第三方运行时 |
| 自动化 | 无 Siri、无 App Intents、无快捷指令 |
| 网络 | 无（0.4.0 起已删除联网 AI） |
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
- Marketing Version：`0.9.3`
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

首次启动没有交易，首页会显示空状态。点击右下角 FAB，选择“📝 记一笔”记录第一笔收入或支出，或选择“⚡ 极速记账”拍照/选图；手动极速文本输入仍在小 AI 入口，不需要麦克风或语音权限。

工程包含 `LedgerBoxTests` Target，可在 Mac 上通过 `Cmd+U` 或 `xcodebuild test` 运行。当前 57 个测试已在 GitHub Actions 的 iPhone 16 / iOS 26.2 模拟器通过（run `39623029691`）；真机仍需你本地验证。

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
    Settings/                        设置、模板、CSV、更新日志
    Main/                            五 Tab 容器
    QuickEntry/                      一句话解析、小 AI、金钱小模型、财务大脑、大脑可视化
  Resources/
    LedgerBox.xcdatamodeld/          Core Data 模型
    Assets.xcassets/                 AppIcon 占位
    FinanceMindWeights.bin           41,943,200 字节 Int8 权重 + Float32 bias
LedgerBoxTests/                      XCTest：财务规则、极速记账解析、财务大脑
.github/workflows/                   无签名 iOS 归档、模拟器测试
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

- 无登录、无账号、无云同步、无广告、无内购；账本只在本机。
- 0.4.0 起不含联网 AI，不含 `URLSession` 请求，不上传账本或输入文本。
- 数据只写入本机 Core Data SQLite。
- CSV 只通过系统文件导出器保存到用户选择的位置。

### 小 AI 文本记账

- `QuickEntryParser` 只依赖 Foundation + `NaturalLanguage`，不依赖 UI/Core Data。
- 解析“微信买奶茶 15 元”得到金额、分类、账户与备注；无法唯一匹配时要求手动补全，不静默猜测。
- `QuickEntryAI` 做本地解释、字段完整度、示例和建议；本地解析不联网，输入文本不会离开设备。
- 已移除语音识别、麦克风和语音识别权限；App 不再请求麦克风。
- 已删除 App Intents、快捷指令和 Siri 入口；不再注册系统自动化，也不会后台写账。

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

- GitHub Actions 已实际 archive，57 个 XCTest 已在模拟器通过；但未签名、未真机安装、未 TestFlight/App Store 验证。
- 没有在真机或模拟器里做截图级视觉验收；“大脑”页面的动画、Canvas 和自适应布局只经过编译和静态检查。
- 已有 `Assets.xcassets` 与 1024×1024 AppIcon 占位；未做上架截图/视觉审查。
- 无账户管理 UI、无分类管理 UI；默认账户与分类由 Persistence 种子和模板创建。
- 无周期记账 UI；需求中的“补记本期”尚未接入页面。
- `SavingsGoal` 与 `Account` 没有 Core Data 关系或 `accountId` 外键；买车页通过 `templateTag` + 专户名称同步。
- 买车页的目标当前金额以专户余额为准，手动编辑目标金额后会在下次进入买车页时被同步覆盖。
- 本月结余只允许结转一次；结转后又新增收入，不能再次结转。
- `AppSettings.themeMode` / `accentColorHex` 字段存在，但当前主题实际由 `ThemeManager` + UserDefaults 驱动，两者未双向同步。
- 无多币种换算；`currencyCode` 默认 CNY，v1 只按 CNY 展示。
- 当前 57 个测试覆盖财务汇总、退款、预算进度、副业分账、结余优先级、金额分位存储、14 个极速记账解析用例、11 个财务大脑模型/计算路由用例、4 个本地教练用例，以及 19 个图片解析/商户词库/去重/转账手续费/写入撤销用例；已在 iPhone 16 / iOS 26.2 模拟器全部通过。
- 已取消 Siri、快捷指令和 App Intents，不能监听银行/微信通知，也没有系统自动化写账入口。
- 小 AI 是本地规则 + `NaturalLanguage` + 5,643 参数金钱分类器 + 41,943,080 参数财务意图模型，不是生成式大模型；新模型合成验证集 98.3% 只代表合成语料回归，真实短句、方言和错别字仍需你自己考。
- 新版未签名 IPA：`LedgerBox-unsigned-0.9.2-UnifiedBar.ipa`，1,790,306 字节，SHA-256 `282C18997C053FC0808A1441B0F5ADB9509E74FFCF2C276EB76F2FF3F07E750D`；无 `PlugIns`、无麦克风/语音/Siri 权限，含相机/相册用途说明，需自签后安装。
- 权重文件 SHA-256：`6F5E92B17EC300D7A0C69AB79324903AE4407FB992393140BB2F783B7355F380`，41,943,200 字节。
- 源码包：`LedgerBox-source-0.9.2-UnifiedBar.zip`；大小与 SHA-256 见同目录 `LedgerBox-0.9.2-SHA256.txt`，源码包不包含自身哈希。
- 当前默认是单 target：不嵌入 `PlugIns/LedgerBoxWidget.appex`，所以 `lcsign` 只需签主 App。Widget 源码仍在仓库中，但不会进入 IPA。
- 如果要重新启用小组件，必须在 Xcode 中恢复 Embed 阶段，并同时签主 App 与 appex；否则会出现图标有、点不开的安装失败。

---

## 文档

- [`Docs/DESIGN_REFERENCE.md`](Docs/DESIGN_REFERENCE.md)：UI 设计参考与落地（Revolut 式金融排版、卡片等高、动效边界）
- [`Docs/UI_INTERACTION_AUDIT.md`](Docs/UI_INTERACTION_AUDIT.md)：键盘/触控/颜色静态审计与未验证边界
- [`Docs/COMPONENTS.md`](Docs/COMPONENTS.md)：架构、文件地图、数据流、扩展点
- [`Docs/FINANCE_RULES.md`](Docs/FINANCE_RULES.md)：16 条边界、公式、模板规则
- [`Docs/BUILD_STEPS.md`](Docs/BUILD_STEPS.md)：Xcode 构建、运行、常见错误
- [`Docs/WINDOWS_BUILD_SIGN.md`](Docs/WINDOWS_BUILD_SIGN.md)：Windows 限制、macOS 无签名构建、自签边界
- [`Docs/ACCEPTANCE.md`](Docs/ACCEPTANCE.md)：P0/P1/P5 验收清单、静态证据、已知缺口
- [`Docs/THEMING.md`](Docs/THEMING.md)：主题令牌、明暗配色、扩展方式
- [`Docs/GITHUB_RESEARCH.md`](Docs/GITHUB_RESEARCH.md)：开源 iOS 记账项目调研与可借鉴项
- [`Docs/QUICK_ENTRY_PARSER.md`](Docs/QUICK_ENTRY_PARSER.md)：物品/金额识别、型号与数量过滤、价格软提醒
- [`Docs/MONEY_BRAIN.md`](Docs/MONEY_BRAIN.md)：5,643 参数金钱小模型、训练边界
- [`Docs/FINANCE_MIND.md`](Docs/FINANCE_MIND.md)：41,943,080 参数财务意图模型、40 个意图、AI 计算路由与规则边界
- [`Docs/OPEN_SOURCE_10.md`](Docs/OPEN_SOURCE_10.md)：10 个开源记账项目的许可证与取舍
- [`CHANGELOG.md`](CHANGELOG.md)：面向用户的版本更新记录
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：贡献流程与硬规则

---

## 许可证

MIT License，见 [`LICENSE`](LICENSE)。

---

## 免责声明

本项目是记账工具源码，不构成财务、税务或投资建议。使用前请自行备份数据，并在自己的 Mac 上完成编译、测试和签名验证。
