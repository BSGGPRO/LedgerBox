# LedgerBox 0.8.0 — 图片记账 / 玻璃顶栏 / 全局 FAB

本文记录 0.8.0 的实现边界、接口契约和验收门禁。所有“已通过”只指 GitHub Actions
`macos-15` 的未签名归档或模拟器 XCTest；没有真机安装、截图级视觉验收或真实账单
准确率测试。

## 1. 产品与 AI 架构

### 1.1 为什么不是 LoRA

当前端侧模型 `FinanceMind` 是 **20,971,560 参数的哈希线性分类器**：

- 40 个财务意图；
- 524,288 个字符 1–3 gram 哈希桶；
- Int8 权重 + Float32 bias；
- 输入文本 → 哈希特征 → 40 类 logits → softmax。

它不是 Transformer，没有注意力层，也没有可注入的低秩适配器。对当前模型做
“LoRA”在数学上没有对应位置；强行宣称 LoRA 生效是不诚实的。真正要 LoRA，必须
先换成 Transformer/MiniMind 类模型，并重新准备训练、量化和端侧推理，这不是本次
0.8.0 的范围。

本次采用 **“事实层 + 词库层 + 模型分类层 + 弃权层”** 的组合，用可测量的错误路径
替代“参数翻倍”：

1. **事实层（规则）**：金额、日期、订单号只由 `ReceiptParser` 提取。模型不生成
   金额、日期、订单号，避免幻觉。
2. **词库层（确定性）**：`MerchantLexicon` 做繁体/全角归一化、别名、包含匹配、
   Levenshtein ≤ 1 和 bigram Jaccard。瑞幸、星巴克、滴滴、美团等 20+ 商户可直接
   命中。
3. **分类层（本地模型）**：`FinanceMind.probe` 的 top intent 映射到 12 个记账分类；
   词库与模型一致时加分，冲突且证据不足时返回“其他”。
4. **弃权层**：置信度低、margin 小、OCR 低置信度、金额多候选时 `needsReview=true`，
   UI 标黄要求用户核对；绝不自动写账。

“能力翻倍”在这里指 **错误率下降的工程路径**，不是准确率或参数量字面翻倍。没有
真实账单的端到端基准，因此不给出“准确率提升 100%”这类无法证明的数字。

### 1.2 两类模型分工

| 任务 | 归属 | 是否允许生成事实 |
|---|---|---|
| OCR 文本纠错/归一化 | `ReceiptParser.normalize` + 商户词库 canonical | 只做字符/别名归一化 |
| 金额/时间/订单号 | 正则 + `Decimal` + SHA-256 | 不允许模型参与 |
| 消费分类 | `FinanceMind` + `MerchantLexicon` 融合 | 只输出分类与置信度 |
| 最终入账 | 用户确认 + `LedgerService.record` | 模型没有写权限 |

## 2. 图片记账流水线

```text
PhotosPicker / UIImagePickerController
        ↓
VisionOCRService.recognize(cgImage:)
  VNRecognizeTextRequest, .accurate
  zh-Hans + en-US, 按 boundingBox 排序
        ↓
ReceiptParser.parse(text, now, calendar)
  normalize → source → amount candidates → date → order hash
  → fee/withdrawal split → warnings
        ↓
LedgerCategoryClassifier.classify(text, fields)
  FinanceMind.probe(text, limit: 40)
  + MerchantLexicon.match(text)
  + abstention
        ↓
ImportCommitService.makeDraft(from: OCRResult)
  ImportDraft（不可变）
        ↓
ImageLedgerFlowView 草稿预览/编辑
  金额、商户、类型、分类、账户、转入账户、时间、备注、手续费口径
        ↓
ImportCommitService.commit(...)
  duplicate guard → LedgerService.record → ImportHistoryStore.add
        ↓
ImportToastView “撤销” 6 秒
  ImportCommitService.undo(sessionID:)
  → 删除本次 transactionIDs → 恢复余额 → markUndone
```

### 2.1 金额规则

- 支持 `¥`、`￥`、千分位、小数点、全角数字。
- 候选按上下文打分：实付/支付/合计/金额/到账 +2；余额/优惠/红包/积分/订单号/
  服务费 −3。
- 多候选分数接近时标记 `ambiguousAmount`；上限 1000 万；金额始终 `Decimal`。
- 没有明确金额时 `makeDraft` 返回 nil，UI 提示改用手动记账，不生成 0 元账单。

### 2.2 日期规则

- 支持 `今天/昨天/前天 + HH:mm`、`yyyy-MM-dd HH:mm`、`M月d日 HH:mm`。
- 无年份用当前年；超过当前时间 1 天回退上一年。
- 无时间用当天 0 点并标记 `missingDate`。
- 日期通过注入的 `Calendar` 计算，测试固定 `Asia/Shanghai`。

### 2.3 订单号与去重

- 订单号只保存 `SHA256(orderID)`，原文不进入 `ImportSession` / JSON 历史。
- `dedupeKey` 优先用订单哈希；否则用
  `SHA256(source + 归一化商户 + 金额 + 分钟级日期)`。
- `commit` 在**任何余额变更前**检查 `ImportHistoryStore.duplicate(for:)`；重复抛
  `ImportError.duplicate`，不写第二笔。
- 用户修改金额/日期/商户后，确认时重新计算 `dedupeKey`，避免用旧 OCR 值误判。
- 撤销后历史标记 `undone`，同一 dedupeKey 允许重新导入。

### 2.4 转账/提现手续费

`TransferSplit` 明确区分两种口径：

- `feeDeductedFromPrincipal`：到账 = 本金 − 手续费，账户扣款 = 本金；
- `feePaidSeparately`：到账 = 本金，账户扣款 = 本金 + 手续费。

写入时：

1. 转账交易金额使用 `credited`；
2. 手续费 > 0 时额外记一笔支出“转账手续费”；
3. 两笔交易 ID 都写入同一个 `ImportSession`；
4. 撤销时两笔都删除，余额完整回滚。

截图无法证明手续费由哪方承担，UI 必须让用户选择，不猜死。

### 2.5 JSON 契约（导入历史）

`ImportHistory.json` 位于 Application Support/LedgerBox：

```json
[
  {
    "id": "3F0C2F7E-6F3A-4B7A-9E4E-2C6B1D5A8C11",
    "createdAt": "2026-10-21T12:00:00Z",
    "dedupeKey": "9f2c…64hex…",
    "transactionIDs": ["B2A1…", "C3B2…"],
    "status": "committed"
  }
]
```

约束：

- 不存 OCR 原文、订单号原文、金额、商户；
- `status` 只允许 `committed` / `undone`；
- 原子写入；损坏时回退空数组，不让 App 崩溃；
- 测试可注入临时 `fileURL`。

## 3. 前端 UI / 动效

### 3.1 悬浮胶囊顶栏

- `GlassHeaderHost` 用 `ScrollView` + `safeAreaInset(top)`；
- `VisualEffectBlur` 使用 `UIBlurEffect(style: .systemUltraThinMaterialDark)`；
- 胶囊填充 `sRGB(20,20,22) @ 0.72`，1px 白色 0.08 描边；
- 展开 68pt，收缩 52pt；safe-area inset 60/76pt；
- 滚动 offset < −8pt 才收缩；`guard` 防重复状态切换；
- 动画 `.easeInOut(duration: 0.2)`；Reduce Motion 直接切换；
- 标题 22pt/16pt rounded bold，Dynamic Type 下用 `minHeight` 允许增高；
- 不使用系统 navigation bar 背景，避免全宽灰条。

CSS 的 `backdrop-filter: blur(16px)` 在 iOS 上没有等价的固定半径 API；
`systemUltraThinMaterialDark` 是系统材质近似，不能声称像素级一致。

### 3.2 头像与设置

- 首页右上角 `ProfileBadge` → `ProfileMenuView` sheet；
- 本地昵称/头像，存 Application Support JSON；
- 微信/支付宝按钮 `disabled`，文案明确“需要 AppID/SDK/服务端”；
- 不持有 AppSecret、不伪造“已授权”、不读取第三方资料；
- “设置”在资料菜单内用 sheet 打开 `SettingsView`，避免嵌套 NavigationStack。

真实微信/支付宝登录的最小前提：

1. 开放平台 AppID；
2. 官方 SDK / Universal Link；
3. 服务端 `code` 换 `access_token`，AppSecret 不下发；
4. 隐私合规与用户授权页。

这些凭据当前不存在，所以只交付协议/占位和本地资料，不交付假登录。

### 3.3 全局 FAB

- `FloatingActionMenu` 放在 `MainTabView` 的 `bottomTrailing` overlay；
- 主按钮 62pt 圆形，`plus` 展开旋转 45°；
- 两个 46pt 最小高度胶囊：
  - `⚡ 极速记账` → 图片/相机识别；
  - `📝 记一笔` → 手动表单；
- spring `response 0.34 / damping 0.78`；Reduce Motion 只淡入淡出；
- `UIImpactFeedbackGenerator(.soft)`；
- 底部 padding 96pt，避开 49pt tab bar + home indicator；
- 首页内容额外 110pt bottom padding；其它 Tab 仍需真机确认最后一行是否被遮挡。

## 4. P0 / P1 Bug 清单

### P0（阻断记账正确性/隐私）

- [x] 模型生成金额/日期/订单号 → 规则层独占，模型无写权限。
- [x] OCR 结果自动写账 → 必须草稿预览 + 用户确认。
- [x] 重复订单重复入账 → 写前 dedupe + JSON 历史 + 编辑后重算 key。
- [x] 订单号明文落盘 → 只存 SHA-256。
- [x] 撤销不恢复余额 → 逐条 `LedgerService.delete`，两笔手续费一起回滚。
- [x] 转账手续费口径猜死 → 两种模式，用户选择。
- [x] 失败历史写入留下幽灵交易 → 回滚已记录交易。
- [x] 未授权微信/支付宝显示“已登录” → 按钮禁用，明确未接入。
- [ ] 真机相机/相册权限与 OCR 方向 → 需真机验证（当前只有编译/模拟器测试）。
- [ ] 真实微信/支付宝 OAuth → 缺 AppID/SDK/服务端，未实现。

### P1（体验/可访问性）

- [x] 顶栏滚动收缩抖动 → 8pt 阈值 + guard + 200ms。
- [x] 顶栏全宽灰条 → 移除 safe-area inset 背景。
- [x] FAB 遮挡 tab bar → 96pt bottom padding。
- [x] 低置信度硬猜分类 → `other + needsReview`。
- [x] 金额多候选静默选择 → `ambiguousAmount` 警告。
- [x] 日期缺失静默用今天 → `missingDate` 警告。
- [x] 键盘遮住金额输入 → `keyboardDoneBar` + 交互式下滑。
- [ ] 所有 Tab 最后一行避让 FAB → 需逐页真机检查。
- [ ] 大字号/SE/Pro Max 顶栏和 FAB 布局 → 需截图级验收。

## 5. 质量门禁

| 门禁 | 命令/方式 | 通过标准 |
|---|---|---|
| Swift 语法 | tree-sitter-swift | 0 ERROR / 0 missing |
| App 编译 | GitHub Actions `ios-unsigned.yml` | archive success |
| 单元测试 | GitHub Actions `ios-tests.yml` | 52 tests, 0 failed |
| 金额 | XCTest | Decimal 分位、千分位、全角 |
| 去重 | XCTest | 第二次 commit 抛 duplicate，余额不变 |
| 撤销 | XCTest | 余额恢复、session=undone、可重导入 |
| 词库 | XCTest | 瑞幸/滴滴/繁体美团 |
| 弃权 | XCTest | 无信号 → other + needsReview |
| 隐私 | 代码审计 | 无订单号明文落盘、无网络请求 |

明确未做：

- 真机安装/签名；
- 截图级 UI 视觉验收；
- 真实微信/支付宝授权；
- 真实账单端到端准确率；
- 性能/内存/耗电基准；
- LoRA 或 Transformer 替换。
