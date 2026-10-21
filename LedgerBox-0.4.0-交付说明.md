# LedgerBox 0.4.0 交付说明

- 版本：`0.4.0`
- 作者：**Beausoleil** · [Bilibili](https://space.bilibili.com/1477283849)
- 代码提交：`b33319e`（0.4.0 功能与文档）
- 文档：0.4.0 交付说明（构建代码为 `b33319e`，后续仅文档变更）
- 许可证：MIT

---

## 1. 这次做了什么

### 1.1 彻底删除联网 AI

- 删除 `OnlineAI.swift`、`OnlineAIView.swift`。
- 删除设置里的联网 AI 入口、API Key/Keychain 配置、接口地址、连接测试和聊天页。
- 删除 `Docs/ONLINE_AI.md` 及 README/架构文档中的联网入口。
- App 源码不再包含 `URLSession` 网络请求；账本和输入文本都不离开设备。

### 1.2 财务大脑扩展到 10,485,800 参数

```text
40 个意图 × 262,144 个字符 n-gram 哈希桶 + 40 个 bias
= 10,485,800 个参数
```

- 意图从 20 类扩到 40 类，新增：现金流、对账、发票、报销、工资核算、存货、折旧、摊销、增值税、权责发生、备用金、应收账款、应付账款、借款、房贷、房租、水电、医疗、教育、公益。
- 特征从 unigram + bigram 扩到 unigram + bigram + trigram。
- 权重以 Int8 量化后存为 `LedgerBox/Resources/FinanceMindWeights.bin`，**10,485,920 字节**；不再使用巨型 Swift base64 数组。
- Swift 端用 `Data` 映射读取：前 160 字节是 40 个 Float32 bias，后面是 40 × 262,144 个 Int8 权重。
- 推理纯本机 CPU，毫秒级；不依赖 Core ML、不依赖第三方库。

### 1.3 财务大脑可视化

`财务大脑` 页顶部新增“对话 / 大脑”分段控件。切到“大脑”后：

- **意图激活图**：40 个意图节点，按 Softmax 概率着色/放大；top 5 连线到中心。
- **模型体检**：10,485,800 参数、40 意图、262,144 哈希桶、10.0 MB Int8 权重、模型加载状态。
- **实时探针**：输入任意短句，显示前 6 个意图概率、激活特征数、哈希桶数、推理耗时。
- **训练覆盖**：列出全部 40 类。
- **边界说明**：这是意图分类激活图，不是神经元级可解释性，也不是 ChatGPT。

---

## 2. 已验证与未验证

| 项目 | 结果 |
|---|---|
| GitHub Actions 未签名归档 | 成功，run `39591530559`，commit `b33319e` |
| 模拟器 XCTest | **29 passed / 0 failed / 0 skipped**，run `39591706814`，iPhone 16 / iOS 26.2 |
| 未签名 IPA | 已生成并校验 |
| 真机安装 | **未执行** |
| 签名 / TestFlight / App Store | **未执行** |
| 人工逐页 UI / 截图级视觉验收 | **未执行** |
| 真实账本准确率 | **未评估** |
| 真实短信/方言/错别字 | **未评估** |

测试覆盖：9 个财务规则与存储 + 14 个极速记账解析 + 6 个财务大脑模型用例。

---

## 3. 产物

### 3.1 未签名 IPA

- 文件：`LedgerBox-unsigned-0.4.0-FinanceBrain.ipa`
- 大小：**1,240,946 字节**
- SHA-256：`9E00BC3F78141FF2DFB321D8B404C835BF9064B677C9F8A12EA4F3F3136E6010`
- 内含：
  - `Payload/LedgerBox.app/LedgerBox`
  - `Payload/LedgerBox.app/FinanceMindWeights.bin`（10,485,920 字节）
  - `Assets.car`、`Info.plist`、`LedgerBox.momd`
- 无 `PlugIns/`，无 Widget appex，无麦克风/语音/Siri 权限。
- **未签名，不能直接安装**；需要你自己的证书和描述文件重签。

### 3.2 模型权重

- `LedgerBox/Resources/FinanceMindWeights.bin`
- 大小：**10,485,920 字节**
- SHA-256：`FBAE921A209BAF880481E10B91ACADEEE3B324182063CDDDDA7CFE9FB4C7CF74`

### 3.3 源码包

- 文件：`LedgerBox-source-0.4.0-FinanceBrain.zip`
- 大小与 SHA-256 见同目录 `LedgerBox-0.4.0-SHA256.txt`（源码包不能包含自身哈希，因此单独放校验文件）。

源码包包含：`LedgerBox/`、`LedgerBoxTests/`、`LedgerBoxWidget/`、`LedgerBox.xcodeproj/`、`.github/`、`Tools/`、`Docs/`、`README.md`、`CHANGELOG.md`、`CONTRIBUTING.md`、`LICENSE`、`.gitignore` 和本说明。

不包含：旧版 IPA/ZIP、旧交付说明、`.git`、`build/`、`DerivedData`、证书、描述文件、Team ID。

---

## 4. 怎么考它

打开 App → 首页“极速”旁“大脑”，或 设置 → AI → 财务大脑 → 切到“大脑”。

在“实时探针”里试这些句子：

| 输入 | 预期 top 意图 |
|---|---|
| 这个月现金流怎么样？ | 现金流 |
| 报销怎么记 | 报销 |
| 固定资产折旧怎么算 | 折旧 |
| 权责发生制和收付实现制区别 | 权责发生 |
| 客户欠款怎么催 | 应收账款 |
| 增值税进项税 | 增值税 |
| 房贷月供怎么记 | 房贷 |
| 发票怎么开 | 发票 |
| 预算还剩多少 | 预算 |
| 怎么存钱 | 储蓄 |
| 你好 | 其他 |

这些是合成语料训练后的回归样例，**不保证**真实世界任意说法都正确。遇到方言、错别字、长句、混合多个问题时，它可能分错；请以探针显示的概率和你自己的判断为准。

---

## 5. 重要边界

1. **它不是生成式大模型。** 10,485,800 个参数是真实的线性分类器权重，不是把 Qwen 裁层，也不是 LLM。
2. **它不会自动写账。** 所有写入仍走 `LedgerService`；财务大脑只回答/提示。
3. **数字来自本机账本。** 回答里的收入、支出、结余、预算、目标来自 Core Data；模型不生成金额。
4. **训练数据是合成的。** 最近一次合成验证集约 99.1%，只用于回归自测，不代表真实准确率。
5. **没有联网。** 0.4.0 已删除全部网络请求；不存在“把账本上传到云端”的路径。
6. **没有真机/签名验证。** GitHub Actions 只证明 archive 和模拟器测试；IPA 未签名，需要你自签。
7. **没有视觉验收。** “大脑”页面的 Canvas、动画和自适应布局只经过编译和静态检查，未在真机/模拟器人工逐页查看。

---

## 6. 签名与安装

当前 IPA 是未签名产物。你需要：

1. 自备 Apple Developer 证书和 `.mobileprovision`（或使用自己的签名工具）。
2. 用证书重签 `Payload/LedgerBox.app`。
3. 确认 Bundle ID 与描述文件匹配；当前是 `com.example.ledgerbox`，必要时在 Xcode 中改成你自己的。
4. 安装到设备后，首次打开检查账本、财务大脑和大脑页。

仓库不包含证书、描述文件、Team ID，也不提供签名服务。

---

## 7. 作者与许可证

- 作者：**Beausoleil**
- Bilibili：https://space.bilibili.com/1477283849
- 许可证：MIT，见 `LICENSE`

本项目是记账工具源码，不构成财务、税务或投资建议。
