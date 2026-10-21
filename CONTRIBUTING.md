# Contributing to LedgerBox

感谢你愿意改进 LedgerBox。这个项目优先保证**本地优先、金额正确、边界清晰**，而不是堆功能。

在提交 PR 之前，请先确认你的改动符合下面的硬规则与架构边界。

---

## 1. 项目边界

LedgerBox 是一个 iOS 17+ 的本地记账本：

- SwiftUI + Core Data
- 仅本地存储
- 无登录、无账号、无云同步
- 无网络请求
- 无广告、无内购、无付费 SDK
- 无 CocoaPods、无第三方运行时依赖
- 金额使用 `Decimal`，禁止用 `Double` 存储金额

不要引入：

- Firebase、Supabase、自建 API、埋点、崩溃上报
- 付费图表库、付费 UI 组件
- SwiftData
- 证书、Team ID、`.p12`、`.mobileprovision`
- 需要联网才能启动的功能

---

## 2. 架构边界

### `FinanceEngine`

- 只依赖 Foundation 和 `TransactionProviding`
- 不依赖 Core Data、SwiftUI
- 不放任何“买车/学生/奶茶/修机”场景规则
- 不直接读写 `NSManagedObject`

### `LedgerService`

- 是交易写入和账户余额变更的唯一入口
- 新增交易、批量交易、删除交易都必须经过它
- 批量写入必须先校验全部草稿，再一次性保存
- 保存失败必须 `rollback()`

### `TemplateRules` / `TemplateInstaller`

- 只负责场景配置和种子数据
- 不修改通用统计公式
- 应用模板不得删除历史交易
- 应用模板不得重置已有账户余额或目标已存金额
- 切换模板只影响之后的规则

### `Theme`

- 所有颜色、圆角、字号、间距集中在 `Theme`
- 页面不要硬编码十六进制颜色
- 新增颜色先加 Theme 令牌，再在页面使用
- 主要页面必须有浅色/深色 `#Preview`

### QuickEntry / 联网 AI

- `QuickEntryParser` 只依赖 Foundation + NaturalLanguage，不依赖 SwiftUI/Core Data。
- 解析结果缺金额、收支、分类、账户时，必须让用户补全，不能静默猜测后保存。
- 不再添加语音识别、麦克风、Siri、快捷指令或 App Intents；这些入口已在 0.2.2 删除。
- 联网 AI 默认关闭，只能由用户主动点发送触发；不得后台同步账本。
- API Key 只能存 Keychain，不得写入 UserDefaults、源码、日志或仓库。
- 联网回答只作建议，不能绕过 `LedgerService` 自动写账。

### 页面

- 每个主页面必须有空状态
- 每个主页面必须有 `#Preview`
- 删除、模板切换、转账等破坏性操作必须有确认
- 错误提示必须可读，不能只打印到控制台

---

## 3. 财务硬规则

提交涉及金额、预算、目标、统计的改动时，必须逐条检查：

1. 删除交易先回滚余额，再删除记录。
2. 转账只生成一条 Transfer，排除在收入/支出之外。
3. v1 只按 CNY 展示；金额字段使用 Decimal。
4. 周期记账目前是手动“补记本期”，不做后台定时任务。
5. 月预算按自然月；周预算按 ISO 周一到周日；跨月周归开始月份。
6. 删除分类保留历史交易，分类软删除，统计归入“其他”。
7. 预算只约束支出。
8. 退款冲减分类支出；金额不能为负。
9. 使用本地时区与操作时间；允许手动日期，但不能晚于当前时间。
10. 目标达成后显示达成，停止倒计时与自动分配；超额进入可用余额。
11. 只做 CSV 导出，不保存任何凭据。
12. 至少支持浅色/深色；颜色、圆角、字体集中在 Theme。
13. 每个主页面有空状态。
14. 模板切换只影响未来规则，切换前确认。
15. 买车优先级：修机 4,400 → 买车 25,000 → 溢出下一目标。
16. 副业收入至少 70% 进当前目标，最多 30% 进备用金；默认 0.7，手动不能低于 0.7，只影响未来收入。

完整说明见 [`Docs/FINANCE_RULES.md`](Docs/FINANCE_RULES.md)。

---

## 4. 代码风格

- Swift 5.9 编译器，iOS 17 API。
- 缩进 4 空格，不使用 Tab。
- 单行尽量不超过 120 字符。
- 类型名用 `UpperCamelCase`，方法和属性用 `lowerCamelCase`。
- 文件必须完整，不能留下 `...`、`TODO: implement`、空实现或占位符。
- 注释只解释“为什么”，不要复述代码。
- 财务边界注释使用 `[铁律1]`、`[铁律2]`、`[边界N]` 标签。
- 不在 View 中直接写余额变更逻辑。
- 不把 `NSManagedObject` 传入 `FinanceEngine`。
- 金额格式化统一用 `MoneyFormat`。
- 日期区间统一用 `FinanceEngine.interval(for:containing:)`。

---

## 5. 本地验证

Windows 不能编译 SwiftUI。请在 macOS + Xcode 中验证：

```bash
xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

运行测试：

```bash
xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test
```

如果只是做无签名归档：

```bash
xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/LedgerBox.xcarchive \
  archive \
  CODE_SIGNING_ALLOWED=NO
```

> 上面是命令模板，不代表本仓库已经执行或通过。提交 PR 时请贴出你实际运行的命令、Xcode 版本、模拟器型号和结果。

没有 macOS 时，只能做静态检查：

- Swift 语法解析
- `project.pbxproj` 解析
- Core Data 模型 XML 解析
- Scheme / plist 解析
- 检查 BOM、文件引用、Build Phase

静态检查不能替代编译。

---

## 6. PR 清单

提交前逐项确认：

- [ ] 改动符合 16 条边界。
- [ ] 金额仍使用 Decimal。
- [ ] 没有新增网络、登录、云同步、广告、内购。
- [ ] 没有新增 CocoaPods 或未固定版本的 SPM 依赖。
- [ ] 新增文件已加入 Xcode target 的 Sources。
- [ ] 新增颜色/字体/圆角来自 Theme。
- [ ] 新增主页面有空状态和 `#Preview`。
- [ ] 删除/转账/模板切换有确认。
- [ ] 极速记账/小模型/联网 AI 仍遵守本地优先与 `LedgerService` 写入边界。
- [ ] 没有提交 `.p12`、`.mobileprovision`、Team ID、真实个人信息或 API Key。
- [ ] 文档同步更新。
- [ ] 没有声称“已编译/已测试”，除非附上实际命令与结果。

---

## 7. 数据模型变更

- 先改 `LedgerBox.xcdatamodeld`，再改 `ManagedObjects.swift`。
- 实体名保持 `Transaction`，Swift 类名保持 `LedgerTransaction`，避免与 `SwiftUI.Transaction` 冲突。
- v1 使用 UUID 外键，不使用 Core Data relationship；新增关系需要单独论证删除规则与迁移风险。
- 金额字段必须是 Core Data `Decimal`。
- 新增字段要考虑旧数据迁移；不要静默删除用户数据。
- 修改模型后必须在 Mac 上验证持久化容器能加载。

---

## 8. 文档

以下文档需要随代码一起更新：

- `README.md`
- `Docs/COMPONENTS.md`
- `Docs/FINANCE_RULES.md`
- `Docs/BUILD_STEPS.md`
- `Docs/WINDOWS_BUILD_SIGN.md`
- `Docs/ACCEPTANCE.md`
- `Docs/THEMING.md`
- `Docs/GITHUB_RESEARCH.md`（如涉及外部项目调研）

---

## 9. 提交信息

建议使用：

```text
feat: add buy-car side hustle split
fix: rollback balance when deleting transfer
docs: clarify weekly budget boundary
refactor: move template seeds out of FinanceEngine
```

不要使用：

```text
update
fix bug
stuff
```

---

## 10. 安全

- 不提交任何证书、描述文件、Team ID、App Store Connect 凭据。
- 不提交真实账单、真实姓名、真实账户号。
- 示例数据必须是虚构的。
- CSV 导出只在本地进行，不上传。
- 发现安全问题请私下联系维护者，不要公开粘贴敏感数据。

---

## 11. 许可证

贡献的代码默认按 MIT License 授权，见 [`LICENSE`](LICENSE)。
