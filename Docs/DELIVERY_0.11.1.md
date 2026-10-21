# LedgerBox 0.11.1 交付说明

- 版本：`0.11.1`（build 17）
- 提交：`6e31485f16d5ccdc3524228a3740165864528b0b`
- 标签：[`v0.11.1`](https://github.com/BSGGPRO/LedgerBox/releases/tag/v0.11.1)
- 仓库：[github.com/BSGGPRO/LedgerBox](https://github.com/BSGGPRO/LedgerBox)
- 作者：Beausoleil · [Bilibili](https://space.bilibili.com/1477283849)
- 许可：MIT

## 下载

- 未签名 IPA：[LedgerBox-unsigned.ipa](https://github.com/BSGGPRO/LedgerBox/releases/download/v0.11.1/LedgerBox-unsigned.ipa)
- 大小：**482,494,164 字节**
- SHA-256：`80e520eefcdd78ae8b75404dda6c9520227554410b197d2d5eff3c5c54b5a837`
- 没有签名、没有 TestFlight、没有 App Store 包。

## 本版修复

- **浅色/白色主题**：浮动标题胶囊改用浅色 material 和主题表面填充，标题/副标题改用主题文字色；底栏、记账气泡、账户页关闭按钮、图片页关闭按钮不再固定深色。
- **底栏对比度**：浅色主题选中态使用对比度校正后的强调色，未选中态使用次级文字色；深色主题保持原样。

## 本版新增

- **0.5B 真实状态**：财务大脑里的“Qwen2.5-0.5B 本地解释层”显示加载状态、完成次数、拒绝次数、最近一次真实输出和失败原因。
- **真实自检**：点“运行一次真实解释”会用固定示例“支出 123.45，预算 200.00，剩余 76.55”调用 llama.cpp；只有通过数字白名单校验的文本才会显示。模拟器明确显示“模拟器不加载 0.5B”，不伪装成功。
- **设置入口**：设置 AI 区显示 0.5B 状态和真实调用计数，点按可进入财务大脑运行自检。
- **解释边界**：0.5B 仍然只改写确定性结果，不写账、不改金额、不补日期；任何新增数字都会被拒绝并回退。

## 已实际验证

- GitHub Actions **iOS Tests** run `39696122047`：iPhone 16 / iOS 26.2 模拟器，**68 passed / 0 failed / 0 skipped**。
- GitHub Actions **iOS Unsigned Archive** run `39696124947`：archive、打包、模型和框架检查、Release 发布全部成功。
- CI 的 `unzip -l` 检查确认 IPA 内含：
  - `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`（491,400,032 字节，SHA-256 `74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB`）
  - `Frameworks/llama.framework/llama`（ios-arm64，二进制 11,982,920 字节，SHA-256 `B86990922D559C80FC863836C784887DDBAE871C9A1D726015E96936C3EDB3EC`）
- 直接 HEAD 下载地址返回 `200`，`Content-Length` 为 **482,494,164**。
- 0.5B 同一 GGUF 在 Windows llama.cpp b11796 CPU 上做过桌面冒烟，输出保留 `1234.50 / 2000 / 765.50`；**这不等于 iOS 真机验证**。

## 未验证

- 没有在物理 iPhone 上安装、启动或跑完整流程。
- 没有在真机加载 0.5B，未测首 token 延迟、总耗时、内存峰值、发热、Metal 是否成功。
- 没有截图级视觉验收；浅色主题的浮动标题、底栏、气泡和两个关闭按钮需要你实际查看。
- 没有验证你的自签工具是否会重签嵌套的 `Frameworks/llama.framework`。
- 没有验证真实票据的 OCR 切分准确率；行距过密、旋转、表格跨行都可能在核对页需要手动修正。
- 没有验证 JSON 备份在超大账本上的耗时和内存。

## 自签与安装

1. 用自己的 Apple 开发者证书和描述文件重签主 App。
2. **必须同时重签** `Payload/LedgerBox.app/Frameworks/llama.framework`；只签主 App 会导致 0.5B 无法加载，但记账/查询/统计仍可用。
3. 安装后先进入「设置 → AI → Qwen2.5-0.5B 本地解释」，点一次自检；若显示“模拟器不加载 0.5B”以外的失败原因，按 `Diagnostics.json` 的 `qwen_*` 事件排查。
4. 若工具不支持嵌套框架，请换用会处理 `Frameworks` 的自签工具，或移除 `llama.framework` 后仅测试非 AI 功能。

## 已知限制

- 未签名 IPA 不能直接安装；仓库不提供证书、描述文件或 Team ID。
- 0.5B 只做解释，不计算金额、比例、日期，也不写账。
- AI 记一笔要求句子里能识别到账户；缺账户时只列缺失项，不写账。
- JSON 恢复是**替换**不是合并，会删除本机现有账本；备份不含导入历史、诊断日志和 UserDefaults。
- 主题/强调色当前由 `ThemeManager` + UserDefaults 驱动，恢复 `AppSettings` 后可能不同步。
- 多账单切分是启发式规则，不保证每张截图都正确；请以核对页为准。
- `FinanceMind` 是 41,943,080 参数的哈希线性分类器，不是 Transformer/Qwen；0.5B 是独立解释层。
