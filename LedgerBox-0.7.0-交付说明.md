# LedgerBox 0.7.0 交付说明

- 版本：`0.7.0`
- 作者：**Beausoleil** · [Bilibili](https://space.bilibili.com/1477283849)
- 开源地址：https://github.com/BSGGPRO/LedgerBox
- 代码提交：`fa093de`
- 许可证：MIT
- 交付日期：2026-10-21

---

## 1. 这次先解决你遇到的键盘问题

之前金额输入用的是 iOS `decimalPad`，它没有 Return 键。SwiftUI 默认不会因为输入结束、切到分类或点一下卡片就自动收键盘，所以你只能上下滑动页面，或者退出页面。

0.7.0 的做法不是只加一个按钮，而是把输入焦点统一管起来：

- 新增 `LedgerBox/Design/KeyboardDismiss.swift`：
  - `.keyboardDoneBar`：键盘上方固定一个“完成”按钮，所有输入页都能直接点。
  - `.keyboardDismissOnBlankTap`：点卡片外空白收起。
  - `@FocusState` 显式管理焦点，保存、取消、解析、切页都会清空。
- 已接入 8 个输入页面：记一笔、极速记账、预算、目标、买车/副业、财务顾问、财务大脑探针、设置 HEX。
- 金额输完后点“完成”立即收起；切换账户、分类、日期后也会自动收起。
- 下滑页面使用 `.scrollDismissesKeyboard(.interactively)`，边滑边收。
- 设置页与财务大脑在同一导航栈时，去掉设置页重复的键盘工具栏，避免出现两个“完成”按钮。

> 说明：键盘工具栏在 SwiftUI 中由系统合并，点空白能否穿透卡片背景、键盘是否完全遮挡输入框，**必须真机确认**。当前仓库没有 UI 测试，不能写成“已真机验证”。

---

## 2. UI 与配色重做

### 2.1 首页 / 设置 / 主 Tab

- 首页右上角只保留一个用户图标 `person.crop.circle`，点进去就是设置；去掉与底部重复的“加号”。
- 视觉从“大阴影 + 高饱和”改为扁平金融风：
  - 20pt 卡片圆角、20pt 卡片内边距、8pt 基础间距。
  - 胶囊主按钮、细描边、细分隔线，无重阴影。
  - 金额、目标、预算、统计卡片统一最小高度，减少一边高一边低。
  - 本月三列在无障碍大字号下自动改为竖排。
  - 金额统一 `ledgerMoneyLine`，单行缩放，不截断。

### 2.2 颜色与自定义强调色

- 新增 `surfaceSunken`、`tertiaryText`、`borderStrong`、`incomeSoft` / `expenseSoft` / `warningSoft` 等 token。
- 默认 5 套强调色：绿、蓝、橙、紫、玫红。
- 支持 `ColorPicker` 和 HEX 输入，实时预览。
- `onAccent` 不再恒白：按强调色亮度自动选白字或近黑字；浅绿、浅黄也能读。
- 文字/图标统一用 `accentText`（对比度校正版），填充/背景才用原始 `accent`。
- 非法 HEX 会提示并保持原色；对比度不足会提示“改用加深版”。

### 2.3 触控与无障碍

- 统计翻月、记账类型条、分段控件、买车“选择”等触控区补到约 44pt。
- 字体改用语义字号，支持 Dynamic Type。
- 财务大脑动画读取“减弱动态效果”：开启后停自动巡演、固定 Canvas 相位。

---

## 3. 财务大脑仍然是 20,971,560 参数

这次没有继续堆参数，也没有塞 Qwen/MiniMind：

```text
40 个意图 × 524,288 个字符 n-gram 哈希桶 + 40 个 bias
= 20,971,560 个参数
```

- 权重：Int8，`FinanceMindWeights.bin` **20,971,680 字节**，SHA-256 `506931280D71A7FC13AB7F38CEDF8CB5916D85F2BE22D3FCB4BDF3D003A320BC`。
- 读取：`Data(options: .mappedIfSafe)`，本机 CPU 推理。
- 它仍是 **40 类哈希线性意图分类器**，不是生成式 LLM。
- 合成验证集约 98.5%，只用于回归自测，**不代表真实世界准确率**。
- 回答中的金额全部来自本机 Core Data / `Decimal` 公式，不由模型生成，也不会自动写账。

---

## 4. 已验证与未验证

| 项目 | 结果 |
|---|---|
| GitHub Actions 未签名归档 | **成功**，run `39602446769`，commit `fa093de` |
| 模拟器 XCTest | **33 passed / 0 failed / 0 skipped**，run `39602690412`，iPhone 16 / iOS 26.2 |
| 未签名 IPA | 已生成并校验，版本 `0.7.0`，内含 20,971,680 字节模型 |
| 静态语法 | tree-sitter-swift 34 个文件解析通过 |
| 真机安装 | **未执行** |
| 签名 / TestFlight / App Store | **未执行** |
| 人工逐页 UI / 截图级视觉验收 | **未执行** |
| 键盘工具栏合并 / 点空白穿透 / 遮挡 | **未真机验证** |
| 真实账本准确率 | **未评估** |

边界必须说清楚：**远程 archive 成功不等于真机安装成功；模拟器测试通过不等于视觉验收通过。**

---

## 5. 产物

### 5.1 未签名 IPA

- 文件：`LedgerBox-unsigned-0.7.0-KeyboardUI.ipa`
- 大小：**1,462,132 字节**
- SHA-256：`5BC51F9FB95CBDADD0E336FC006B0421AB0FC9D1CEBECEA92EF812A38223A240`
- Bundle ID：`com.example.ledgerbox`
- 版本：`0.7.0 (1)`
- 内含：
  - `Payload/LedgerBox.app/LedgerBox`
  - `Payload/LedgerBox.app/FinanceMindWeights.bin`（20,971,680 字节）
  - `Assets.car`、`Info.plist`、`LedgerBox.momd`
- 无 `PlugIns/`，无 Widget appex，无麦克风/语音/Siri 权限。
- **未签名，不能直接安装**；需要你自己的证书和描述文件重签。

### 5.2 源码包

- 文件：`LedgerBox-source-0.7.0-KeyboardUI.zip`
- 大小与 SHA-256 见同目录 `LedgerBox-0.7.0-SHA256.txt`。
- 包含：`LedgerBox/`、`LedgerBoxTests/`、`LedgerBoxWidget/`、`LedgerBox.xcodeproj/`、`.github/`、`Tools/`、`Docs/`、`README.md`、`CHANGELOG.md`、`CONTRIBUTING.md`、`LICENSE`、`.gitignore` 和本说明。
- 不包含：旧版 IPA/ZIP、旧交付说明、`.git`、`build/`、`DerivedData`、证书、描述文件、Team ID、`design-ref/` 参考仓库。

### 5.3 模型权重

- `LedgerBox/Resources/FinanceMindWeights.bin`
- 大小：**20,971,680 字节**
- SHA-256：`506931280D71A7FC13AB7F38CEDF8CB5916D85F2BE22D3FCB4BDF3D003A320BC`

---

## 6. 怎么验这次改动

### 6.1 键盘

1. 首页 → “记一笔” → 点金额，输入 `12.34`。
2. 键盘上方应出现“完成”；点它，键盘应落下。
3. 再输入金额，点“分类”并选一个分类，键盘也应落下。
4. 极速记账、预算、目标、买车/副业、财务顾问、财务大脑探针重复一次。
5. 如果某个页面仍要上下滑才收，请记录：页面名、iOS 版本、机型、键盘类型。

### 6.2 配色

1. 首页右上角用户图标 → 设置 → 外观。
2. 依次点 5 个预设色，观察“记一笔”胶囊上的文字是否始终可读。
3. 用 ColorPicker 选一个很浅的颜色，按钮文字应自动变深；文字/图标使用加深版。
4. 输入非法 HEX（如 `ZZZZZZ`），应提示且不改色。

### 6.3 财务大脑

设置 → AI → 财务大脑 → 切到“大脑”：

- 模型体检应显示 **20,971,560 参数**、**524,288 哈希桶**、**20.0 MB**。
- 不输入，等约 4.4 秒，问题应自动巡演；点“暂停巡演”可停。
- 输入自己的问题，点“探测”，应显示 top 6 意图和延迟。

---

## 7. 怎么安装未签名 IPA

Windows 没有 Xcode，不能本地签名。可选：

1. 用 Mac 的 Xcode / Apple Configurator 重签。
2. 用 iOS 签名工具（如 lcsign、Sideloadly 等）导入自己的证书和描述文件。
3. 用 TrollStore 等支持未签名安装的环境（仅限对应系统版本）。

IPA 的 Bundle ID 是 `com.example.ledgerbox`；正式分发前请改成你自己的 Bundle ID，并替换签名证书。

---

## 8. 这次仍然没做的事

- 没有在 Mac 上打开 Xcode 逐页点选。
- 没有真机安装、没有截图、没有深色/浅色逐页视觉验收。
- 没有 UI 自动化测试；键盘、触控、颜色仍靠人工确认。
- 没有真实账本准确率、性能、内存、长时间运行测试。
- 没有签名、TestFlight、App Store 上架材料。

这些不是“已经完成”，而是明确留给你在 Mac/真机上验收的部分。
