# LedgerBox 构建与运行步骤

本文面向 macOS + Xcode 环境。Windows 不能直接编译 SwiftUI，请先阅读 [`WINDOWS_BUILD_SIGN.md`](WINDOWS_BUILD_SIGN.md)。

> 本文命令是操作模板，不代表本仓库已经执行或通过。请在你的 Mac 上实际运行并记录结果。

---

## 1. 环境

| 项目 | 要求 |
|---|---|
| macOS | 建议 macOS 14+ |
| Xcode | 建议 Xcode 15+ |
| iOS Deployment Target | 17.0 |
| Swift 编译器 | 5.9+；工程语言模式 `SWIFT_VERSION = 5.0` |
| 依赖 | 无 CocoaPods、无第三方 SPM |
| 设备 | iOS 17 模拟器或真机 |

检查 Xcode：

```bash
xcodebuild -version
xcrun simctl list devices available
```

---

## 2. 打开工程

```bash
open LedgerBox.xcodeproj
```

确认：

- Scheme：`LedgerBox`
- Target：`LedgerBox`
- Bundle ID：`com.example.ledgerbox`
- Deployment Target：`17.0`

共享 Scheme 位于：

```text
LedgerBox.xcodeproj/xcshareddata/xcschemes/LedgerBox.xcscheme
```

---

## 3. 模拟器运行

1. 选择任意 iOS 17 模拟器。
2. `Product → Run` 或 `Cmd+R`。
3. 首次启动会自动创建：
   - `现金账户`
   - 默认支出/收入分类
4. 首页无交易时显示空状态。
5. 点击“记一笔”，先记录一笔收入，再记录一笔支出。

模拟器运行不需要开发者账号。

### 重置模拟器数据

如果 Core Data 模型改动后出现旧 store 不兼容：

```bash
xcrun simctl erase all
```

或在 Simulator 菜单中 `Device → Erase All Content and Settings`。

> 这会清空模拟器数据，不会影响真机。

---

## 4. 真机运行

1. 连接 iPhone。
2. 在 Xcode `Signing & Capabilities` 选择自己的 Team。
3. 修改 Bundle ID 为你自己的唯一 ID。
4. 选择真机运行。

注意：

- 不要把 Team ID、证书、描述文件提交到仓库。
- 不要在源码中写死开发者账号。
- 真机签名属于你自己的本地配置。

---

## 5. Preview

主要页面都有 `#Preview`：

- 首页浅色/深色
- 新增交易浅色/深色
- 统计浅色/深色
- 预算浅色/深色
- 流水浅色/深色
- 目标浅色/深色
- 主 Tab 浅色/深色
- 设置浅色/深色
- 买车页浅色/深色

如果 Preview 崩溃，优先检查：

1. 是否注入 `PersistenceController.preview.container.viewContext`。
2. 是否注入 `ThemeManager()`（首页/主 Tab/设置需要）。
3. 是否注入了 `\.ledgerTheme`。
4. 是否有 `@FetchRequest` 依赖的实体未在模型中。

---

## 6. 命令行构建

### 6.1 查看 scheme

```bash
xcodebuild -project LedgerBox.xcodeproj -list
```

### 6.2 模拟器 Debug 构建

把 `iPhone 15` 换成你本机可用的模拟器：

```bash
xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

如果模拟器名称不存在，先执行：

```bash
xcrun simctl list devices available
```

### 6.3 不签名 Release 归档

```bash
mkdir -p build

xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/LedgerBox.xcarchive \
  archive \
  CODE_SIGNING_ALLOWED=NO
```

产物：

```text
build/LedgerBox.xcarchive/Products/Applications/LedgerBox.app
```

### 6.4 打包未签名 IPA

这一步只是把 `.app` 放进 `Payload` 并压缩，不做签名：

```bash
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R build/LedgerBox.xcarchive/Products/Applications/LedgerBox.app build/ipa/Payload/
cd build/ipa
zip -r ../LedgerBox-unsigned.ipa Payload
cd ../..
```

得到：

```text
build/LedgerBox-unsigned.ipa
```

> 该 IPA 未签名，不能直接安装到普通 iPhone。你需要使用自己的证书与描述文件自行签名。本项目不提供证书、Team ID 或签名自动化。

### 6.5 运行测试

共享 scheme 已加入 `LedgerBoxTests` 的 Test Action：

```bash
xcodebuild \
  -project LedgerBox.xcodeproj \
  -scheme LedgerBox \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

测试目标当前包含 23 个测试：

- 收入/支出/退款/转账汇总
- 账户过滤
- 分类支出退款冲减
- 预算进度与超预算
- 副业 70% 下限
- 买车结余优先级
- 金额保留两位小数（15.5 / 15.555 / 15.554）
- 内存 store 保存 1234.56 元后读回仍为 1234.56，删除后余额回滚为 0
- 极速记账：金额/别名/收支推断/负金额/多金额/全角数字/超长输入/未匹配分类与账户
- 物品识别：电动车型号 `M5200` 不被当金额；口红价格 1000 识别为支出并给出软提醒；`2台` 数量不压过价格

> 已在 GitHub Actions 的 iPhone 16 / iOS 26.2 模拟器实际运行：23 passed / 0 failed（run `39584757968`）。本机命令模板仍可能因 Xcode 版本和模拟器名称不同而需要调整。

---

## 7. 常见构建错误

### 7.1 `No such module 'Charts'`

- `Charts` 是系统框架，不需要 SPM。
- 确认 Deployment Target ≥ 16；本项目要求 17.0。
- 确认使用 Xcode 15+。

### 7.2 `Transaction` 与 SwiftUI 冲突

- Core Data 实体名是 `Transaction`。
- Swift 类名是 `LedgerTransaction`。
- 如果新增代码使用 `Transaction` 作为类型，可能命中 `SwiftUI.Transaction`。请使用 `LedgerTransaction`。

### 7.3 `Cannot find 'BuyCarPlanView' in scope`

- 确认 `BuyCarPlanView.swift` 已加入 target 的 Compile Sources。
- 确认文件在 `Features/Goals/` 下。
- 在 Xcode 中检查 Target Membership。

### 7.4 `Cannot find type 'LedgerDraft' in scope`

- `LedgerDraft` 定义在 `Finance/LedgerService.swift`。
- 确认 `LedgerService.swift` 已加入 target。
- 确认没有把文件误移到未加入 target 的目录。

### 7.5 `@EnvironmentObject ThemeManager` 运行时崩溃

崩溃信息通常类似：

```text
No ObservableObject of type ThemeManager found
```

修复：

- 首页、主 Tab、设置页需要 `.environmentObject(ThemeManager())`。
- 真实 App 由 `LedgerBoxApp` 注入。
- Preview 必须显式注入。

### 7.6 Core Data 模型找不到

检查：

- `LedgerBox.xcdatamodeld` 是否在 target 中。
- `NSPersistentContainer(name: "LedgerBox")` 名称是否一致。
- `.xccurrentversion` 是否指向 `LedgerBox.xcdatamodel`。
- 模型是否有编译错误。

### 7.7 旧 store 不兼容

开发期修改模型后可能出现：

```text
The model configuration used to open the store is incompatible with the one that was used to create the store
```

模拟器可清空数据；真机需要迁移或删除 App 后重装。不要在没有迁移方案时直接改已发布模型。

### 7.8 签名错误

模拟器不需要签名。  
命令行归档使用 `CODE_SIGNING_ALLOWED=NO`。  
真机需要你自己的 Team 与证书，本项目不提供。

### 7.9 `project.pbxproj` 解析异常

本仓库的 `project.pbxproj` 是手写工程文件：

- 必须是 UTF-8 无 BOM。
- 新增文件必须同时出现在 `PBXFileReference`、`PBXBuildFile`、分组、Sources 阶段。
- 不要用会重排 object ID 的工具随意改写。

### 7.10 静态检查通过但 Xcode 报错

静态检查只能验证：

- Swift 语法树
- pbxproj 结构
- XML/plist 结构

它不能替代 Swift 类型检查、SwiftUI 宏展开、Core Data 代码生成和链接。以 Xcode 实际报错为准。

### 7.11 语音与 Siri 权限已移除

0.2.0 起不再使用 `Speech` / `AVAudioEngine`；0.2.2 进一步删除 Siri / 快捷指令。当前不再注入：

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSSiriUsageDescription`

`LedgerIntents.swift` 已删除，App target 不再包含 `AppIntents`、`AppShortcutsProvider` 或 `AddTransactionIntent`。如果真机仍然弹出麦克风/Siri 权限，说明装的是旧 IPA。

### 7.12 快捷指令里找不到 LedgerBox

这是预期行为。0.2.2 起已取消 Siri、快捷指令和 App Intents；0.3.0 继续不添加。不要再添加 `NSSiriUsageDescription`，也不要把 `LedgerIntents.swift` 加回 target。

---

## 8. 本仓库当前仍缺的东西

- `Assets.xcassets` 与 AppIcon 已随 archive 编译；仍未做真机/视觉检查。
- `LedgerBoxTests` 已加入并实际运行：23 个测试通过（iPhone 16 / iOS 26.2 模拟器，run `39584757968`）。
- `.github/workflows/ios-unsigned.yml` 已实际运行：run `39584745878`，结论 success。
- 新版未签名 IPA 已生成：`LedgerBox-unsigned-0.3.1-Parser.ipa`（890,146 字节，含物品/金额识别、15,380 参数财务意图模型、本地小 AI、5,643 参数金钱模型、可选联网 AI、更新日志，无语音/Siri 权限，无 `PlugIns`）。
- Widget Extension 源码保留，但当前**不嵌入** `Payload/LedgerBox.app/PlugIns/`；这是为了兼容只签主 App 的 `lcsign`。需要小组件时再恢复 Embed 阶段并签 appex。
- Widget 未配置 App Group，因此即使重新嵌入也不读取真实账本。
- 没有证书、描述文件、Team ID。
- 已有远程 archive 与模拟器测试记录；仍缺真机运行、签名和安装记录。

---

## 9. 建议的首次运行顺序

1. 启动 App，确认首页空状态。
2. 记录收入 500。
3. 记录支出 32.50。
4. 记录一笔转账。
5. 查看流水、统计、预算。
6. 新建预算。
7. 新建目标。
8. 打开设置，切换浅色/深色/强调色。
9. 应用“买车攒钱”模板。
10. 回到目标页，进入买车计划。
11. 打卡、记副业、结转、记奶茶。
12. 导出 CSV。
13. 删除一笔交易，确认余额回滚。

---

## 10. 相关文档

- [`COMPONENTS.md`](COMPONENTS.md)
- [`FINANCE_RULES.md`](FINANCE_RULES.md)
- [`WINDOWS_BUILD_SIGN.md`](WINDOWS_BUILD_SIGN.md)
- [`ACCEPTANCE.md`](ACCEPTANCE.md)
- [`THEMING.md`](THEMING.md)
