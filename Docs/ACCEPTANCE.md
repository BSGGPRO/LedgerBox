# LedgerBox 验收清单

本文是当前交付的验收记录。它区分三类结论：

- **源码具备**：文件与结构存在，可通过静态检查。
- **部分**：规则或 UI 只实现了一部分。
- **未验证**：需要真机、签名、人工 UI 验收或真实网络环境。
- **缺失**：当前仓库没有该产物。

> 已在 GitHub Actions 执行 `xcodebuild archive` 和 `xcodebuild test`；没有在本地 Mac 上执行 `codesign`，也没有真机安装。不要把“模拟器测试通过”写成“真机已验证”。

---

## 1. 验收结论

| 项目 | 结论 |
|---|---|
| 静态源码 | 34 个 Swift 文件（29 个 App + 2 个 Widget + 3 个测试） |
| 文档 | README、LICENSE、.gitignore、CONTRIBUTING、核心 Docs、开源调研与 10 项目清单 |
| 静态语法 | tree-sitter-swift 解析通过 |
| 工程结构 | pbxproj / XML / plist 解析通过；App + Widget Extension 两个 Target，Widget 默认不嵌入 |
| 实际编译 | GitHub Actions `macos-15` archive 成功（run `39602446769`，commit `fa093de`） |
| 实际运行 | 33 个 XCTest 在 iPhone 16 / iOS 26.2 模拟器通过（run `39602690412`）；App UI 未人工逐页验收 |
| 签名/IPA | `LedgerBox-unsigned-0.7.0-KeyboardUI.ipa` 已生成；未签名、未真机安装 |
| Assets/AppIcon | 已随 archive 编译；未做视觉/真机验证 |
| GitHub Actions | 已实际运行，结论 success |
| 测试 Target | 已加入；33 个测试在模拟器全部通过 |
| 最终交付 | 源码、文档、未签名 IPA；模拟器测试通过，签名/真机未执行 |

---

## 2. 静态证据

最后一次静态检查结果：

```text
SWIFT SYNTAX OK 34
XML/PLIST/PBX OK 41 37
NO BOM
```

解释：

- `34`：34 个 `.swift` 文件（29 个 App + 2 个 Widget + 3 个测试）；编译结论以 GitHub Actions archive 为准。
- `42`：`PBXFileReference` 数量（28 个 App Swift + 2 个 Widget Swift + 3 个测试 Swift + 图标/框架/产品/Info.plist/模型资源等）。
- `38`：`PBXBuildFile` 数量（App 源文件 + Widget 源文件 + 测试源文件 + 模型/资源/框架；Widget 不再嵌入，因此没有 appex 嵌入项）。
- `NO BOM`：`project.pbxproj` 为 UTF-8 无 BOM。

其他静态检查：

| 检查 | 结果 |
|---|---|
| `URLSession` | 未发现；0.4.0 起已删除联网 AI；无 CloudKit / Firebase / Supabase / 自建后端 |
| `@NSManaged var ... Double` | 未发现 |
| `Podfile` / `Package.swift` / `Package.resolved` / `.xcworkspace` | 未发现 |
| `#Preview` | 14 个 Swift 文件包含 |
| 主页面空状态 | 首页、流水、统计、预算、目标、买车页具备 |
| 证书/描述文件/Team ID | 未发现 |
| 文档 + 调研/10 项目清单 | 已创建 |
| AppIcon | 1024×1024、RGB、无 alpha；未做视觉审查 |
| Asset Catalog JSON | `Contents.json` 可解析；已随 archive 编译 |
| Assets 工程引用 | 文件引用 + Resources build phase 已存在 |
| GitHub Actions | `.github/workflows/ios-unsigned.yml` 已实际运行成功（run `39602446769`） |
| 测试 Target | `LedgerBoxTests` 已加入；3 个测试源文件；33 个测试通过 |
| Scheme Test Action | 已加入 `TestableReference` 与 `MacroExpansion`；`xcodebuild test` 已实际执行 |

这些检查不能替代：

- 真机安装、签名、TestFlight/App Store
- 人工逐页 UI/深色模式/无障碍验收
- 真实账本、真实网络与弱网环境
- 长时间运行和性能/内存测试

---

## 3. P0 硬规则检查

| # | 规则 | 状态 | 说明 |
|---|---|---|---|
| P0-1 | iOS 17+ SwiftUI + Core Data | 源码具备 | Deployment Target 17.0；无 SwiftData |
| P0-2 | 账本仅本地 Core Data；无登录/云/广告/内购 | 源码具备 | 账本不离开本机；0.4.0 起不含联网 AI；无第三方 SDK |
| P0-3 | 金额 Decimal，不用 Double 存钱 | 源码具备 | 模型金额为 Decimal；`@NSManaged` 无 Double；UI 比例使用 Double；解析文本在边界转 Decimal；落库前统一 `roundedToCents()` 保留两位 |
| P0-4 | 颜色/圆角/字体集中在 Theme | 源码具备 | Theme + ThemeManager + EnvironmentKey；页面使用 theme 令牌 |
| P0-5 | 每个主页面有空状态 | 源码具备 | 六个数据页面均有空状态 |
| P0-6 | 每个主页面有 `#Preview` | 源码具备 | 13 个文件含 Preview，含浅色/深色/小组件 |
| P0-7 | 无 CocoaPods、无第三方 SPM | 源码具备 | 无 Podfile / Package.swift |
| P0-8 | 仓库无证书/Team ID/密钥 | 源码具备 | 未发现 p12/mobileprovision/Team ID |
| P0-9 | 16 条边界 | **部分** | 核心交易/预算/退款/转账/模板/买车已实现；周期记账 UI、分类删除 UI、目标自动分配等仍缺 |
| P0-10 | 通用引擎与场景规则分离 | 源码具备 | FinanceEngine 不依赖 Core Data/SwiftUI；TemplateRules 独立 |
| P0-11 | 单一写入边界 | 源码具备 | LedgerService 负责 record/recordBatch/delete |
| P0-12 | README / LICENSE / .gitignore / CONTRIBUTING | 源码具备 | 均已创建 |
| P0-13 | Docs 核心文档 | 源码具备 | COMPONENTS / FINANCE_RULES / BUILD_STEPS / WINDOWS_BUILD_SIGN / ACCEPTANCE / THEMING；另有 GITHUB_RESEARCH、OPEN_SOURCE_10、CHANGELOG |
| P0-14 | Assets.xcassets / AppIcon | 源码具备（占位） | 1024×1024 PNG + Contents.json；已随 archive 编译，未做视觉检查 |
| P0-15 | GitHub Actions 无签名归档 | 已运行成功 | `.github/workflows/ios-unsigned.yml`；run `39602446769` |
| P0-16 | 测试 Target | 已运行通过 | `LedgerBoxTests`；33 个测试在模拟器通过（run `39602690412`） |
| P0-17 | 实际编译/运行/签名 | **部分** | 远程 archive 成功；模拟器测试通过；签名/真机未验证 |
| P0-18 | 不虚假宣称已编译/已签名 | 文档具备 | README 与 Docs 区分模拟器测试、签名与真机 |

---

## 4. P1 功能验收矩阵

以下除特别标注外均为 **未人工运行**，需要在 macOS/Xcode 或真机中逐项验证；表格中的“解析器单元测试通过”仅指对应 XCTest，不代表 UI 自动化。

| # | 场景 | 预期 | 状态 |
|---|---|---|---|
| P1-1 | 首次启动 | 自动创建现金账户与默认分类；首页空状态 | 未运行 |
| P1-2 | 新增收入 | 账户余额增加；首页/流水/统计更新 | 未运行 |
| P1-3 | 新增支出 | 账户余额减少；预算进度更新 | 未运行 |
| P1-4 | 新增转账 | 一条 Transfer；两边余额变化；不计收支 | 未运行 |
| P1-5 | 新增退款 | 账户余额增加；分类支出冲减 | 未运行 |
| P1-6 | 删除收入/支出 | 余额回滚；统计重算 | 未运行 |
| P1-7 | 删除转账 | 转出/转入都回滚 | 未运行 |
| P1-8 | 流水筛选/搜索 | 类型、备注、分类、账户可筛选 | 未运行 |
| P1-9 | 预算新增/编辑/删除 | 总/分类预算、月/周、启停用 | 未运行 |
| P1-10 | 预算超限 | 进度与警告正确 | 未运行 |
| P1-11 | 统计图表 | 6 个月柱状图、分类环图、累计趋势 | 未运行 |
| P1-12 | 目标新增/编辑/删除 | 进度环、倒计时、达成状态 | 未运行 |
| P1-13 | 主题切换 | 浅色/深色/强调色即时生效并持久化 | 未运行 |
| P1-14 | 模板应用 | 日常/学生/买车；二次确认；历史不删 | 未运行 |
| P1-15 | CSV 导出 | UTF-8 BOM；字段转义；无凭据 | 未运行 |
| P1-16 | 买车打卡 | 每天一次 +100 | 未运行 |
| P1-17 | 买车固定工资 | 每月一次 +500 | 未运行 |
| P1-18 | 买车年度补贴 | 每年每档一次 | 未运行 |
| P1-19 | 副业 70/30 | 比例下限 70%；优先级分账；原子保存 | 未运行 |
| P1-20 | 本月结余结转 | 只算现金；优先级；每月一次 | 未运行 |
| P1-21 | 奶茶预算 | 150/月、2 杯/周告警 | 未运行 |
| P1-22 | 目标专户警告 | 支出/转出提醒 | 未运行 |
| P1-23 | Preview | 各页面浅色/深色可渲染 | 未运行 |
| P1-24 | 小 AI 文本解析 | 一句话识别金额/收支/分类/账户/物品；跳过型号与数量；价格软提醒 | 解析器单元测试通过；UI 未人工验收 |
| P1-25 | 权限收敛 | 已移除麦克风/语音识别/Siri 权限；不再请求这些权限 | 未运行 |
| P1-26 | Siri / App Intents | 已取消 Siri、快捷指令和 App Intents；不再注册系统自动化 | 静态具备 |
| P1-27 | WidgetKit 小组件 | 源码保留；当前默认不嵌入 appex，避免自签失败 | 未运行 |
| P1-28 | 更新日志/作者入口 | 设置页可打开 Changelog 与 Beausoleil Bilibili | 未运行 |
| P1-29 | 无联网 AI | 0.4.0 已删除接口、Keychain 和网络请求 | 源码具备 |
| P1-30 | 财务大脑 | 41,943,080 参数、40 意图；9 类公式由模型路由、Decimal 精确执行；不联网、不写账、不生成数字；含可视化探针 | 未运行；合成集准确率不代表真实 |

---

## 5. P5 交付检查

| # | 项目 | 状态 |
|---|---|---|
| P5-1 | README 说明项目、构建、限制 | 具备 |
| P5-2 | MIT LICENSE | 具备 |
| P5-3 | .gitignore 覆盖 Xcode/证书/构建产物 | 具备 |
| P5-4 | CONTRIBUTING 说明硬规则与 PR 清单 | 具备 |
| P5-5 | Docs 核心文档 + 调研/10 项目清单 | 具备 |
| P5-6 | 版本号 0.3.1 / Bundle ID 占位 | 具备 |
| P5-7 | 无 DEVELOPMENT_TEAM | 具备 |
| P5-8 | Assets/AppIcon | 已有占位，已随 archive 编译，未视觉验证 |
| P5-9 | GitHub Actions workflow | 已实际运行，run `39602446769` success |
| P5-10 | 测试 Target | 已加入（3 个测试源文件），33 个测试通过 |
| P5-11 | 实际 Xcode 编译 | GitHub Actions archive 成功（commit `d791803`） |
| P5-12 | 实际运行 | 33 个 XCTest 在 iOS 26.2 模拟器通过；App UI 未人工验收 |
| P5-13 | 未签名 IPA | `LedgerBox-unsigned-0.7.0-KeyboardUI.ipa`（1,462,132 字节，无 PlugIns、无麦克风/语音/Siri 权限，适合 lcsign）；run `39602446769` |
| P5-14 | 自签验证 | 未执行 |
| P5-15 | 截图/视觉回归 | 缺失 |
| P5-16 | 本地化 | 缺失（仅中文） |
| P5-17 | Dynamic Type / 无障碍专项 | 部分 |
| P5-18 | 数据迁移方案 | 缺失（v1 初始模型） |
| P5-19 | 网络/隐私声明 | 文档具备；0.4.0 起无 `URLSession`、无联网 AI |
| P5-20 | 不虚假宣称编译/签名 | 文档具备 |

---

## 6. 已知阻塞与缺口

### 6.1 必须先补的交付物

1. `Assets.xcassets` 与 AppIcon 已随 archive 编译；仍需真机/视觉检查。
2. GitHub Actions workflow 已实际触发，run `39602446769` 成功。
3. `LedgerBoxTests` 的 33 个测试已在 iPhone 16 / iOS 26.2 模拟器通过（run `39602690412`）。
4. 已有远程 archive 与模拟器测试记录；仍缺真机运行、签名和安装记录。
5. 未签名 IPA 已生成并通过结构校验；签名与安装未验证。

### 6.2 功能缺口

1. 周期记账 UI 未接入“补记本期”。
2. 分类管理/软删除 UI 未接入。
3. 账户管理 UI 未接入。
4. `SavingsGoal` 与 `Account` 无外键；买车目标按名称/标签同步。
5. 目标达成后的自动分配/超额划转未实现。
6. 模板切换会更新当前预算/目标规则，严格“只影响未来”需产品确认。
7. 周预算跨月归属没有独立持久化。
8. 本月结余结转每月只能一次，结转后新增收入不能再次结转。
9. 无多币种换算。
10. `AppSettings` 主题字段与 `ThemeManager` 未同步。
11. Widget 未配置 App Group，只能显示静态 UI，不能读取真实账本。

### 6.3 工程缺口

1. 测试 Target 已运行：33 个测试在 iOS 26.2 模拟器通过。
2. CI 工作流已实际运行并 archive 成功；仍需真机运行。
3. Assets/AppIcon 已随 archive 编译；未做视觉/真机检查。
4. 无截图。
5. 无迁移版本。
6. 无本地化文件。
7. 固定字号，未接入 Dynamic Type。
8. 本地未运行 Xcode；模拟器测试通过不代表真机无崩溃或 UI 无布局问题。

---

## 7. 手工验收步骤（Mac）

1. `open LedgerBox.xcodeproj`
2. 选择 iOS 17 模拟器，Run。
3. 确认首页空状态。
4. 记录收入 500。
5. 记录支出 32.50。
6. 记录退款 10（同分类）。
7. 记录转账 100 到另一个账户。
8. 打开流水，筛选四种类型，搜索备注。
9. 删除转账，确认两边余额回滚。
10. 新建总预算 2,000，支出 2,100，确认超预算。
11. 退款 100，确认回到刚好 2,000。
12. 打开统计，确认柱状图/环图/趋势线。
13. 新建目标 5,000，当前 1,200，确认倒计时。
14. 打开设置，切换浅色/深色/五种强调色。
15. 应用“买车攒钱”模板。
16. 回到目标页，进入买车计划。
17. 打卡 +100，重复打卡应被阻止。
18. 记固定工资 +500，重复应被阻止。
19. 记年度补贴 3,000，重复应被阻止。
20. 副业 1,000，比例 70%，确认修机/买车/备用金分账。
21. 结转本月现金结余，确认每月一次。
22. 记奶茶 160，确认月上限警告；本周第 2 杯确认周警告。
23. 从目标专户直接支出，确认警告。
24. 首页点“极速”，输入“微信买奶茶 15 元”，确认分类/账户/金额，保存后首页刷新。
25. 点示例胶囊“支付宝打车 32.5”，确认小 AI 状态卡、分类建议、账户建议和字段完整度更新。
26. 打开系统“快捷指令”搜索 LedgerBox，确认没有 Siri/快捷指令入口；设置中也不应出现 Siri 权限。
27. 导出 CSV，用文本编辑器/Excel 检查中文与字段。
28. 归档 `CODE_SIGNING_ALLOWED=NO`，确认产物。

任何一步失败，都应以 Xcode 控制台/崩溃日志为准，而不是以静态检查结论为准。

---

## 8. 最终验收决定

### 8.1 已完成

- 34 个 Swift 文件（29 个 App + 2 个 Widget + 3 个测试）。
- Xcode 工程、共享 scheme、App target、`LedgerBoxTests` target。
- Core Data 模型、持久化、主题、财务引擎、全部主页面。
- 小 AI 文本记账：纯 Foundation 解析器、`QuickEntryAI` 本地解释、字段完整度、示例/分类/账户建议、5,643 参数金钱分类器。
- 物品/金额识别：电动车、口红两个示例；跳过型号/数量；口红高价软提醒；新增 3 个解析测试。
- 已删除联网 AI：0.4.0 起不再包含接口、Keychain、连接测试或聊天页。
- 已移除语音识别、麦克风、语音识别权限与 Siri；App Intents / 快捷指令已删除。
- 设置页更新日志入口、`ChangelogView`、根目录 `CHANGELOG.md`。
- WidgetKit Extension target 与源码保留；当前默认不嵌入 App，避免 `PlugIns` 嵌套签名失败。
- 设置页作者入口：Beausoleil 的 Bilibili 个人空间。
- README、MIT LICENSE、.gitignore、CONTRIBUTING。
- Docs 核心文档 + GitHub 开源调研 + `OPEN_SOURCE_10.md` 10 项目清单。
- Assets.xcassets 与 1024×1024 AppIcon 占位。
- `.github/workflows/ios-unsigned.yml`。
- `LedgerBoxTests` 的 33 个测试（9 个财务规则与存储 + 14 个极速记账解析 + 6 个财务大脑 + 4 个本地教练）。
- 静态检查：Swift 语法、pbxproj、scheme、XML、plist、JSON、文档链接、BOM。

### 8.2 未执行，不能声称

- 本地 Mac/Xcode 手工运行；已在 GitHub Actions 的 iPhone 16 / iOS 26.2 模拟器运行。
- 真机安装、签名、TestFlight、App Store。
- Widget 读取真实账本数据：当前未配置 App Group，小组件是静态 UI。
- 小组件在真机主屏幕上的视觉回归；当前 IPA 默认不包含小组件。
- 网络/隐私的运行时验证（0.4.0 起已无网络请求，不需要联网测试）。

### 8.3 已知功能缺口

- 周期记账 UI 未接入“补记本期”。
- 分类管理/软删除 UI 未接入。
- 账户管理 UI 未接入。
- `SavingsGoal` 与 `Account` 无外键。
- 目标达成后的自动分配/超额划转未实现。
- 周预算跨月归属未独立持久化。
- 模板切换会更新当前预算/目标规则，严格“只影响未来”需产品确认。
- `AppSettings` 主题字段与 `ThemeManager` 未同步。
- 无多币种换算。
- iOS 不允许读取其他 App 的通知内容；已取消 Siri/快捷指令，不能“监听银行/微信通知”后完美复刻商业记账 App。
- 本地小 AI 是规则 + 5,643 参数分类器 + 41,943,080 参数财务意图模型，不是生成式模型；财务大脑未做真实账本准确率测试；0.4.0 起不含联网 AI。

这些缺口不阻塞“静态源码 + 文档”交付，但阻塞“生产可用/已验证”结论。

### 8.4 结论

> **按“源码、archive 与模拟器测试”目标：完成。**  
> **按“已签名、可真机安装、生产可用”目标：未验证。**  
> 本项目不声称已签名、已真机安装或已通过 App Store 验证；未签名 IPA 不能直接安装。

最终源码包：`LedgerBox-source-0.3.1-Parser.zip`（大小与 SHA-256 见交付说明）。旧版源码包不含物品/金额识别与 0.3.1 测试，不再作为最新交付。

---

## 9. 相关文档

- [`COMPONENTS.md`](COMPONENTS.md)
- [`FINANCE_RULES.md`](FINANCE_RULES.md)
- [`BUILD_STEPS.md`](BUILD_STEPS.md)
- [`WINDOWS_BUILD_SIGN.md`](WINDOWS_BUILD_SIGN.md)
- [`THEMING.md`](THEMING.md)
- [`GITHUB_RESEARCH.md`](GITHUB_RESEARCH.md)
- [`FINANCE_MIND.md`](FINANCE_MIND.md)
- [`MONEY_BRAIN.md`](MONEY_BRAIN.md)
- [`../README.md`](../README.md)
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
