# GitHub 开源 iOS 记账项目调研

本文记录一次 **GitHub Search API 元数据检索**，用于给 LedgerBox 的功能取舍提供参考。检索时间：2026-10。没有逐行审计这些仓库的源码，也没有复制任何代码。Star 数与描述会变化，以下只代表检索时看到的信息。

## 1. 检索到的项目

| 项目 | 检索时 Star | 许可证 | 描述中值得注意的点 |
|---|---:|---|---|
| [sameersyd/Expenso-iOS](https://github.com/sameersyd/Expenso-iOS) | 743 | Apache-2.0 | SwiftUI、Core Data、Charts、Face/Touch ID、CSV、MVVM |
| [alfianlosari/SwiftUICDExpenseTrackerCompleted](https://github.com/alfianlosari/SwiftUICDExpenseTrackerCompleted) | 336 | MIT | SwiftUI + Core Data 的完整示例 |
| [BearTS/actual-budget-app](https://github.com/BearTS/actual-budget-app) | 285 | 未识别（NOASSERTION） | 原生 SwiftUI 客户端；Summary widget、App Intents；连接 Actual Budget 服务 |
| [PinkXaciD/Squirrel](https://github.com/PinkXaciD/Squirrel) | 23 | GPL-3.0 | 强调快速、直观、隐私的本地记账 |
| [VintusS/Inpenso](https://github.com/VintusS/Inpenso) | 25 | MIT | 现代 iOS 支出跟踪、分析图表 |
| [hkalexling/Buck_Tracker](https://github.com/hkalexling/Buck_Tracker) | 37 | 未声明 | Swift 编写的 iOS 支出跟踪器 |

> “未识别/未声明”不等于可以随便用。没有明确许可证的仓库默认保留所有权利，不能把代码复制进 MIT 项目。

## 2. 与 LedgerBox 的对比

### 已经对齐或更强的部分

- **SwiftUI + Core Data**：与 Expenso、SwiftUICDExpenseTracker 的技术路线一致；LedgerBox 额外把财务计算拆成纯 Foundation 的 `FinanceEngine`，并把写入集中到 `LedgerService`。
- **图表与 CSV**：Expenso 也有 Charts/CSV；LedgerBox 已具备 6 个月趋势、分类环图、累计结余和 UTF-8 BOM CSV。
- **本地优先/隐私**：与 Squirrel 的方向一致；LedgerBox 无登录、无云同步、无网络请求。
- **App Intents**：Actual Budget 客户端也提供 App Intents；LedgerBox 现在同时提供结构化记账与一句话解析两种入口。
- **空状态/主题**：LedgerBox 的主题令牌、浅色/深色 Preview 与空状态比多数示例更完整。

### 可以借鉴、但本次不直接引入

1. **Face ID / Touch ID 应用锁**（Expenso 的描述提到生物识别）
   - 适合用 `LocalAuthentication`，不引入第三方 SDK。
   - 需要处理“首次进入”“从后台回前台”“失败回退”的 UX；不能把锁做成假安全。
2. **WidgetKit 小组件**（Actual Budget 的 Summary widget）
   - 真正的桌面/锁屏小组件必须新增 WidgetKit extension target，不能只靠 `LedgerIntents.swift`。
   - 可以先做“本月支出/预算进度”只读组件，再考虑快速记账。
3. **隐私清单与本地化**
   - 增加 `PrivacyInfo.xcprivacy`、中文/英文本地化、Dynamic Type 与无障碍标签。
   - 这些是上架与长期维护项，不影响当前静态源码结构。
4. **分类/账户管理 UI**
   - 多数完整记账 App 都允许用户管理分类和账户；LedgerBox 目前仍依赖种子数据与模板。
5. **搜索/筛选体验**
   - LedgerBox 已有类型、备注、分类、账户搜索；可继续做保存筛选条件、按月快速跳转。
6. **深度链接**
   - 用 `ledgerbox://quick-entry` 从快捷指令直接打开极速记账面板；当前 App Intents 已能在后台写入，深度链接属于下一步 UX 优化。

### 明确不采纳

- 银行/PSD2 同步、云账户、订阅制：违反“本地优先、无网络 API”的交付约束。
- 第三方 LLM/云端推理：违反“小 AI 在本地、无网络”的目标；当前采用规则 + `NaturalLanguage` + 字段完整度，不接生成式模型。
- 直接复制 GPL-3.0 或无许可证仓库的代码：LedgerBox 是 MIT，不能混入不兼容许可证的代码。
- “读取其他 App 通知自动记账”：iOS 沙盒不允许；快捷指令只能处理系统允许的分享文本、短信/邮件、个人自动化输入。

## 3. 本次已落实的优化

- 首页增加“极速”入口，保留原“记一笔”完整表单。
- `QuickEntryParser` 将一句话解析为金额、收支、分类、账户、备注；缺项不静默猜测。
- 0.2.0 移除语音输入，改为纯文本小 AI；不请求麦克风/语音识别权限。
- `AddTransactionIntent` + `QuickAddIntent` + `AppShortcutsProvider` 接入快捷指令/Siri。
- App Intents 通过主上下文串行写入，仍复用 `LedgerService`。
- 保留 11 个解析测试与 Siri 文案；移除麦克风/语音识别权限。

## 4. 建议的下一轮

优先级从高到低：

1. 在 Mac/Xcode 上实际编译并运行 20 个测试，修正类型/宏/链接问题。
2. 给小 AI 记账补 UI 测试与“保存后首页刷新”的真机验证。
3. 增加 `PrivacyInfo.xcprivacy` 与应用锁（LocalAuthentication）。
4. 新增 WidgetKit extension，做只读月度摘要。
5. 补分类/账户管理 UI 与深度链接。
6. 完成中文本地化与 Dynamic Type/无障碍审查。

## 5. 许可证提醒

- MIT/Apache-2.0 项目的**思路与接口设计**可以参考；如果复制实质代码，必须保留版权与许可证声明。
- GPL-3.0 代码不能直接并入 MIT 项目，除非整个项目接受 GPL 兼容安排。
- 没有 LICENSE 的仓库不要复制代码。
- 本文只做元数据层面的调研，不构成对上述项目代码质量、安全性或维护状态的担保。
