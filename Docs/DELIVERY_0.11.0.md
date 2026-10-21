# LedgerBox 0.11.0 交付说明

- 版本：`0.11.0`（build 16）
- 提交：`410376cc50d9de6cb22ac5d2557cc63944ca736c`
- 标签：[`v0.11.0`](https://github.com/BSGGPRO/LedgerBox/releases/tag/v0.11.0)
- 仓库：[github.com/BSGGPRO/LedgerBox](https://github.com/BSGGPRO/LedgerBox)
- 作者：Beausoleil · [Bilibili](https://space.bilibili.com/1477283849)
- 许可：MIT

## 下载

- 未签名 IPA：[LedgerBox-unsigned.ipa](https://github.com/BSGGPRO/LedgerBox/releases/download/v0.11.0/LedgerBox-unsigned.ipa)
- 大小：**482,469,078 字节**
- SHA-256：`6A34A040239BD2D9D2A829309878BD058F8DC4CA0C85332B4131265C700DDE07`
- 没有签名、没有 TestFlight、没有 App Store 包。

## 本版新增

- **一张图多账单**：按 OCR 行距和分隔符切分，无法解析金额的文本块合并到邻近账单，单图最多 20 笔。
- **多账单核对**：逐笔修改商户、金额、日期、收支、分类、账户、备注；可排除重复项；顶部批量账户/转入账户选择。
- **整批入账**：全部成功才保留，中途失败撤销已写入部分；成功提示可一次撤销整批并恢复余额。
- **JSON 全量备份/恢复**：账户、分类、流水、预算、目标、模板、设置；导入前校验 schema、UUID、引用、金额和日期，失败 `rollback`。
- **财务大脑动作路由**：记一笔、查账、导出 CSV、导出 JSON、图片记账；写账和导出前必须点确认；记一笔成功后可直接撤销。
- **诊断日志**：`Application Support/LedgerBox/Diagnostics.json`，最多 500 条，只记录事件和计数。
- **0.5B 保护**：生成中拒绝卸载；可手动卸载；解释上限 96 token、温度 0.10；加载/生成失败自动回退。

## 已实际验证

- GitHub Actions **iOS Tests** run `39689066193`：iPhone 16 / iOS 26.2 模拟器，**68 passed / 0 failed / 0 skipped**。
- GitHub Actions **iOS Unsigned Archive** run `39689667610`：archive、打包、模型和框架检查、Release 发布全部成功。
- CI 的 `unzip -l` 检查确认 IPA 内含：
  - `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`（491,400,032 字节，SHA-256 `74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB`）
  - `Frameworks/llama.framework/llama`（ios-arm64，二进制 11,982,920 字节，SHA-256 `B86990922D559C80FC863836C784887DDBAE871C9A1D726015E96936C3EDB3EC`）
- 0.5B 同一 GGUF 在 Windows llama.cpp b11796 CPU 上做过桌面冒烟，输出保留 `1234.50 / 2000 / 765.50`；**这不等于 iOS 真机验证**。

## 未验证

- 没有在物理 iPhone 上安装、启动或跑完整流程。
- 没有在真机加载 0.5B，未测首 token 延迟、总耗时、内存峰值、发热、Metal 是否成功。
- 没有截图级视觉验收；多账单卡片、嵌套 `fileExporter`、AI 动作卡的实际呈现需要你测试。
- 没有验证你的自签工具是否会重签嵌套的 `Frameworks/llama.framework`。
- 没有验证真实票据的 OCR 切分准确率；行距过密、旋转、表格跨行都可能在核对页需要手动修正。
- 没有验证 JSON 备份在超大账本上的耗时和内存。

## 自签与安装

1. 用自己的 Apple 开发者证书和描述文件重签主 App。
2. **必须同时重签** `Payload/LedgerBox.app/Frameworks/llama.framework`；只签主 App 会导致 0.5B 无法加载，但记账/查询/统计仍可用。
3. 安装后先在「设置 → 数据」做一次 JSON 备份，再测试多账单和 AI 动作。
4. 若工具不支持嵌套框架，请换用会处理 `Frameworks` 的自签工具，或移除 `llama.framework` 后仅测试非 AI 功能。

## 已知限制

- 未签名 IPA 不能直接安装；仓库不提供证书、描述文件或 Team ID。
- 0.5B 只做解释，不计算金额、比例、日期，也不写账。
- AI 记一笔要求句子里能识别到账户；缺账户时只列缺失项，不写账。
- JSON 恢复是**替换**不是合并，会删除本机现有账本；备份不含导入历史、诊断日志和 UserDefaults。
- 主题/强调色当前由 `ThemeManager` + UserDefaults 驱动，恢复 `AppSettings` 后可能不同步。
- 多账单切分是启发式规则，不保证每张截图都正确；请以核对页为准。
- `FinanceMind` 是 41,943,080 参数的哈希线性分类器，不是 Transformer/Qwen；0.5B 是独立解释层。
