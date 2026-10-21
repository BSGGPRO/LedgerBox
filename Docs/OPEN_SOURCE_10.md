# 10 个开源记账 / 个人财务 iOS 项目

检索时间：2026-10-21。星标数为 GitHub API 当时返回值，会随时间变化。

筛选口径：

- iOS / Swift 为主，能直接参考 SwiftUI、Core Data、预算、统计或小组件实现。
- 优先选择许可证清晰的仓库；许可证不是 OSI 标准的项目单独标注。
- **只参考交互、信息架构和工程取舍，不复制代码。** GPL / Apache-2.0 的代码不能直接搬进 MIT 项目。

| # | 项目 | 星标 | 许可证 | 可借鉴点 |
|---|---|---:|---|---|
| 1 | [rafsoh/dimeApp](https://github.com/rafsoh/dimeApp) | 1,894 | GPL-3.0 | iOS 原生视觉、快速记账、预算与图表；适合看“记账 App 如何做得不像表格”。 |
| 2 | [sameersyd/Expenso-iOS](https://github.com/sameersyd/Expenso-iOS) | 743 | Apache-2.0 | SwiftUI + Core Data + Charts + MVVM + CSV 导出 + Face/Touch ID，和 LedgerBox 的技术栈最接近。 |
| 3 | [alfianlosari/SwiftUICDExpenseTrackerCompleted](https://github.com/alfianlosari/SwiftUICDExpenseTrackerCompleted) | 336 | MIT | 最小可读的 Core Data + SwiftUI 记账示例；适合核对基础 CRUD 与汇总结构。 |
| 4 | [VintusS/Inpenso](https://github.com/VintusS/Inpenso) | 25 | MIT | 现代支出分析、预算管理；可看统计页与预算页的信息层级。 |
| 5 | [PinkXaciD/Squirrel](https://github.com/PinkXaciD/Squirrel) | 23 | GPL-3.0 | 本地优先、隐私导向的轻量记账；可看“不登录也能用”的产品表达。 |
| 6 | [IEEE-VIT/Xpendi](https://github.com/IEEE-VIT/Xpendi) | 16 | MIT | 学生团队项目，结构简单；适合看小型记账 App 的页面拆分。 |
| 7 | [adityask98/Hotaru](https://github.com/adityask98/Hotaru) | 16 | GPL-3.0 | Firefly III 的非官方 iOS 客户端；可看远程账本、API 同步与本地缓存的边界。 |
| 8 | [DeimanteValunaite/SwiftUI-Expense-Tracker](https://github.com/DeimanteValunaite/SwiftUI-Expense-Tracker) | 11 | MIT | 纯 SwiftUI 练习项目；适合看轻量表单、列表和分类汇总。 |
| 9 | [ck3g/homebugh-ios](https://github.com/ck3g/homebugh-ios) | 3 | MIT | 家务/支出混合记账，数据模型较小；可看“非典型记账场景”的字段取舍。 |
| 10 | [pshptr/Wallety-ExpenseTracker](https://github.com/pshptr/Wallety-ExpenseTracker) | 3 | Apache-2.0 | SwiftUI 入门级支出记录；可看最小可用的新增/列表/汇总闭环。 |

## 额外参考（不计入 10 个）

- [BearTS/actual-budget-app](https://github.com/BearTS/actual-budget-app)：285 星，GitHub 许可证字段为 `NOASSERTION`，使用前必须自行确认许可证。它的 Summary widget、App Intents 和 Actual Budget 同步值得看，但**不能因为“开源”就默认可以复制**。
- [DarkRioStudio/AutoLedger](https://github.com/DarkRioStudio/AutoLedger)：`NOASSERTION`，多平台本地优先记账，含只读视图；同样需要先确认许可证。

## 对 LedgerBox 的直接取舍

| 方向 | 参考项目 | LedgerBox 的选择 |
|---|---|---|
| Core Data + SwiftUI | Expenso、SwiftUICDExpenseTracker | 保留手写 `NSManagedObject`，不引入第三方 ORM。 |
| 预算 / 统计 | dimeApp、Inpenso | 只做本地汇总，不接云端账本。 |
| CSV 导出 | Expenso | 已实现本地 CSV，不申请网络权限。 |
| 生物识别 | Expenso | 暂不加入；没有 `PrivacyInfo.xcprivacy` 与真机验证前不声称支持。 |
| 小组件 | actual-budget-app | 新增 WidgetKit 小组件，但不做 App Group 共享账本，避免自签描述文件不匹配。 |
| 多币种 / 云同步 | Hotaru、actual-budget-app | v1 仍只做 CNY + 本地存储。 |

## 许可证提醒

- **MIT**：保留版权与许可声明后可使用、修改、再分发。
- **Apache-2.0**：保留许可证与 NOTICE，修改文件需标注；专利条款需阅读。
- **GPL-3.0**：如果分发衍生作品，通常需要以 GPL 兼容方式开放源代码；不要直接把代码复制进 MIT 的 LedgerBox。
- **NOASSERTION**：GitHub 未能识别标准许可证，不等于“无许可证”，也不等于“可以随便用”。

本文件只做调研记录，不构成法律意见。
