# LedgerBox 0.10.0 交付说明

**版本**：0.10.0 (15)  
**构建**：GitHub Actions run `39632398591`，commit `92a1995`  
**Tag**：`v0.10.0`  
**Release**：https://github.com/BSGGPRO/LedgerBox/releases/tag/v0.10.0

---

## 1. 这次真正装进去了什么

### Qwen2.5-0.5B-Instruct

| 项 | 值 |
|---|---|
| 模型 | Qwen2.5-0.5B-Instruct |
| 量化 | Q4_K_M |
| 文件 | `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` |
| 大小 | 491,400,032 字节 |
| SHA-256 | `74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB` |
| 许可证 | Apache 2.0 |

### llama.cpp 运行时

| 项 | 值 |
|---|---|
| 版本 | `b11796` |
| 框架 | `llama.framework`，`ios-arm64` |
| 框架二进制 | 11,982,920 字节 |
| ZIP SHA-256 | `07460786882E91BD41C2C7F55BA3E163B7F28DF55148B59700F1AB52780A055F` |
| 许可证 | MIT |

### 安装包

| 项 | 值 |
|---|---|
| 文件 | `LedgerBox-unsigned.ipa` |
| 大小 | 482,293,759 字节 |
| SHA-256 | `48137EB3E7CECEC42CE7A1D74B4E9B895431C93E83EFEC21E6259028DDD8BFB1` |
| 版本 | 0.10.0 (15) |
| 签名 | 未签名 |

CI 的 `Verify artifact exists` 与 `Record artifact metadata` 已用 `unzip -l` 验证：

- `Payload/LedgerBox.app/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` 存在，491,400,032 字节。
- `Payload/LedgerBox.app/Frameworks/llama.framework/llama` 存在。
- `FinanceMindWeights.bin` 仍为 41,943,200 字节。

---

## 2. 代码怎么接的

### 运行路径

```text
财务大脑提问
  ↓
FinanceAdvisor：规则 + FinanceMind 选意图
  ↓
Decimal 精算引擎：金额、占比、预算、日期、公式
  ↓
QwenLocalModel：只把结果改写成 2–3 句中文
  ↓
数字校验：解释里的数字必须出现在原结果中
  ↓
通过 → 显示“0.5B 本地解释”
不通过/超时/未加载 → 只显示原来的确定性文案
```

### 关键文件

- `LedgerBox/Features/LocalAI/LedgerLlamaShim.h/.c`
  - 用 `dlopen` 加载 `Frameworks/llama.framework/llama`。
  - 不把 llama 链接进主二进制，所以模拟器可以正常编译和跑测试。
  - `llama_model_load_from_file`、`llama_init_from_model`、tokenize、decode、sampler 全部通过 `dlsym` 解析。
- `LedgerBox/Features/LocalAI/QwenLocalModel.swift`
  - 单例、串行队列、只加载一次。
  - 模拟器返回“模拟器不加载 0.5B”。
  - 模型缺失、框架缺失、加载失败都有明确状态，不阻塞旧功能。
  - 生成结果做数字白名单校验，防止模型新增金额。
- `LedgerBox/Features/QuickEntry/FinanceAdvisorView.swift`
  - 顶部显示 0.5B 状态。
  - 回答卡新增“0.5B 本地解释”区块。
- `Frameworks/llama.framework`
  - 只提交 iOS arm64 slice，不含 dSYM，约 12 MB。
- `Models/`
  - `.gitignore` 排除 `*.gguf`，模型不进 Git；由 CI 下载后打进 Release IPA。
- `iOS Unsigned Archive` workflow
  - 构建前从 `hf-mirror.com` 下载模型，校验 SHA-256。
  - 归档时把模型复制进 `.app`，把 `llama.framework` 复制进 `.app/Frameworks`。
  - 手动 `workflow_dispatch` 时自动创建/更新 `v0.10.0` Release。

---

## 3. 验证结果

### 已验证

- iOS Unsigned Archive：run `39632398591`，**success**。
- IPA 版本 `0.10.0 (15)`。
- IPA 内模型和框架存在，大小正确。
- 源码编译通过；C shim、Swift 包装、桥接头均通过 Xcode 16.4 / iOS 18.5 SDK 编译。
- 0.10.0 的 57 个 XCTest 在 iPhone 16 / iOS 26.2 模拟器通过（run `39633219957`：57 passed / 0 failed / 0 skipped）。
- 模拟器路径明确不加载模型，不会因缺少 arm64 模拟器 slice 而崩溃。

### 桌面冒烟测试（不是 iOS 真机）

用同一个 `b11796` 的 Windows CPU `llama-cli` 加载同一份 GGUF，输入：

```text
计算结果：本月支出 1234.50 元，预算 2000 元，剩余 765.50 元。请用两句话解释。
```

输出：

```text
本月实际支出为 1234.50 元，预算为 2000 元，剩余 765.50 元。
```

- 模型识别为 `Q4_K - Medium`。
- CPU 生成约 51.2 token/s。
- 输出保留了 1234.50 / 2000 / 765.50，没有新增数字。

这只证明 GGUF 文件、Qwen 模板和提示词在桌面 llama.cpp 上可用；**不证明 iOS 真机加载、Metal、内存或耗时**。

### 未验证

- **没有在 iPhone 真机上安装过这个 IPA。**
- **没有在 iOS 真机上实际跑过 0.5B 生成。**
- 没有测过模型加载耗时、首 token 延迟、内存峰值、发热、Metal 是否成功。
- 没有截图级视觉验收。
- 没有做真实账本的 0.5B 中文质量评估。
- 没有验证自签工具是否会正确重签嵌套的 `llama.framework`。

这三项是硬限制，不能用“编译通过”代替。

---

## 4. 已知风险

1. **包体大**：IPA 482 MB，安装后占用更大；首次打开财务大脑会加载约 491 MB 模型。
2. **内存**：Qwen 0.5B + context + App 可能接近或超过部分 4 GB 设备的舒适区；加载失败会回退，不会写坏账。
3. **运行时**：`dlopen` 依赖框架已正确嵌入并签名；如果自签工具漏签嵌套框架，0.5B 会显示加载失败，旧功能仍可用。
4. **生成质量**：0.5B 只做解释，不做计算；数字白名单能拦截新增数字，但不能保证每句中文都自然。
5. **模拟器**：仅有 `ios-arm64` 设备 slice，模拟器不加载，这是有意设计。

---

## 5. 安装

IPA 未签名。请使用你自己的 Apple Developer 证书和 provisioning profile 重签后安装。若使用第三方自签工具，确认它会把 `Payload/LedgerBox.app/Frameworks/llama.framework` 一并签名；否则 0.5B 不可用，但记账功能不受影响。

---

## 6. 结论

0.10.0 已经把**真实 Qwen2.5-0.5B-Instruct Q4_K_M** 和**真实 llama.cpp iOS 运行时**打进 IPA，并接到财务大脑的“解释层”，同时保留 Decimal 精算和数字白名单。

但它还不是“真机验收版”。下一步必须在 iPhone 上确认：

1. 模型能否成功加载；
2. 首 token 和完整 160 token 的耗时；
3. 内存峰值是否安全；
4. 自签后嵌套框架是否可加载；
5. 解释中文是否值得保留。

在完成这五项之前，不应把 0.5B 描述为“已在手机上跑通”。
