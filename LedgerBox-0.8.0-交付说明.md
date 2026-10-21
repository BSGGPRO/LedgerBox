# LedgerBox 0.8.0 交付说明

- 版本：`0.8.0`
- 作者：**Beausoleil** · [Bilibili](https://space.bilibili.com/1477283849)
- 开源地址：https://github.com/BSGGPRO/LedgerBox
- 代码提交：`f4d6f7a`
- 许可证：MIT
- 交付日期：2026-10-21

---

## 1. 四个角色各自交付了什么

### 产品老板

- 把“图片记账”定义成一条可核对、可撤销的流水线，而不是“拍完就自动写账”。
- 明确三条不可妥协的规则：金额/日期/订单号只由规则层负责；OCR 不自动落账；订单号只存哈希。
- 把首页底部“两个按钮”合并成全局 FAB，保留两个清晰动作：
  - `⚡ 极速记账`：相册/相机截图识别；
  - `📝 记一笔`：手动表单。
- 把设置从顶栏移入右上角本地资料菜单，避免顶栏既像设置又像头像。
- P0/P1 清单见第 6 节，未验证项不写成已验证。

### 端侧 AI 架构专家

- **没有替换现有 20,971,560 参数 `FinanceMind`**，也没有声称对它做 LoRA。
- 现有模型是 40 类哈希线性分类器，不是 Transformer；LoRA 没有可注入的注意力层。强行套 LoRA 是概念错误。
- 本次把“能力翻倍”落到误差路径，而不是参数数字：
  1. 事实层：正则 + `Decimal` + SHA-256；
  2. 词库层：40 个商户、别名、繁简/全角归一化、Levenshtein、bigram；
  3. 分类层：`FinanceMind.probe` 的 top intent 映射到 12 个记账分类；
  4. 弃权层：低置信度/冲突 → “其他 + 需核对”，不硬猜。
- 模型低置信度不崩溃；模型不可用时词库仍能工作。
- 反幻觉 prompt 的等价实现：模型没有金额/日期/订单号输出通道，从接口上禁止生成事实。

### 前端 UI/UX 专家

- 首页顶栏改为 `GlassHeaderHost`：
  - `VisualEffectBlur`（`systemUltraThinMaterialDark`）；
  - 填充 `sRGB(20,20,22) @ 0.72`；
  - 1px 白色 0.08 描边；
  - 展开 68pt / 收缩 52pt；
  - 滚动 offset < −8pt 才收缩；
  - `.easeInOut(duration: 0.2)`，Reduce Motion 直接切换；
  - 不使用系统 navigation bar 背景，避免全宽灰条。
- 右上角 `ProfileBadge`：38pt 圆形头像，点开本地资料菜单。
- 设置移入资料菜单，用 sheet 打开，避免嵌套 `NavigationStack`。
- `FloatingActionMenu`：62pt 主按钮，plus 旋转 45°，弹簧 `response 0.34 / damping 0.78`；两个 46pt 动作；底部 96pt padding，避开 tab bar。
- 微信/支付宝按钮保持禁用，文案明确“需要 AppID/SDK/服务端”，不伪造“已授权”。
- CSS `backdrop-filter: blur(16px)` 在 iOS 没有固定半径等价 API；`systemUltraThinMaterialDark` 是系统材质近似，未做像素级比对。

### 项目负责人

- 建立 `ImportDraft` / `ImportSession` / `ImportError` / `ImportHistoryStore` 契约。
- 写入只走 `LedgerService.record`，撤销只走 `LedgerService.delete`，不绕过账本写边界。
- 去重在余额变更前完成；编辑金额/日期/商户后重新计算 dedupe key。
- 转账手续费两种口径都支持，两笔交易同一 session，撤销一起回滚。
- 交付物、哈希、CI run、未验证边界全部写清；不用“本地编译成功”这类无法证明的说法。

---

## 2. 图片记账流水线

```text
相册 / 相机
  ↓
VisionOCRService（VNRecognizeTextRequest，本机）
  ↓
ReceiptParser（金额/日期/订单号/手续费）
  ↓
MerchantLexicon + FinanceMind（分类，低置信度弃权）
  ↓
ImportDraft 草稿预览（可改金额、商户、分类、账户、时间、备注、手续费口径）
  ↓
用户确认
  ↓
去重检查 → LedgerService.record → ImportHistoryStore
  ↓
6 秒 ImportToastView“撤销” → 删除交易 → 恢复余额 → 标记 undone
```

### 金额

- 支持 `¥`、`￥`、千分位、小数、全角数字；
- 实付/支付/合计/金额/到账加分；余额/优惠/红包/积分/订单号/服务费减分；
- 多候选接近标记 `ambiguousAmount`；
- 上限 1000 万；
- 全程 `Decimal`，不经过 `Double`。

### 日期

- 今天/昨天/前天 + HH:mm；
- `yyyy-MM-dd HH:mm`、`M月d日 HH:mm`、ISO `T`；
- 无年份用当前年；未来超过 1 天回退上一年；
- 无时间用当天 0 点并标记 `missingDate`。

### 订单号与隐私

- 订单号只输出 `SHA256`，`ImportSession` / JSON 历史不存原文；
- UI 的“原始识别文本”只存在内存，用于用户核对，不落盘；
- 去重 key 优先订单哈希，否则 `SHA256(source + 商户 + 金额 + 分钟级日期)`；
- 撤销后允许同 key 重新导入。

### 手续费

- 从本金扣除：到账 = 本金 − 手续费，账户扣款 = 本金；
- 另付手续费：到账 = 本金，账户扣款 = 本金 + 手续费；
- 手续费单独记一笔支出；两笔 ID 都进 session，撤销一起删。

---

## 3. 模型与“能力翻倍”的真实边界

```text
40 个意图 × 524,288 个字符 1–3 gram 哈希桶 + 40 个 bias
= 20,971,560 个参数
```

- 权重 Int8，`FinanceMindWeights.bin` 20,971,680 字节；
- SHA-256 `506931280D71A7FC13AB7F38CEDF8CB5916D85F2BE22D3FCB4BDF3D003A320BC`；
- 本机 CPU 推理，不联网；
- 仍是 **哈希线性意图分类器**，不是生成式 LLM、不是 Transformer。

“能力翻倍”在本次交付中的定义是：

- 事实字段错误 → 由正则/词典兜底，模型不接触；
- 低置信度硬猜 → 弃权到“其他 + 需核对”；
- 重复订单 → 写前拦截；
- 误写 → 6 秒撤销并恢复余额。

**没有**真实的端到端准确率翻倍数据，也没有把参数量翻倍；不要把它理解成模型能力字面翻倍。

---

## 4. 已验证

| 项目 | 结果 |
|---|---|
| GitHub Actions 未签名归档 | run `39609649230`，commit `f4d6f7a`，success |
| 模拟器 XCTest | run `39609659199`，52 passed / 0 failed / 0 skipped |
| IPA 版本 | `CFBundleShortVersionString = 0.8.0`，build `8` |
| IPA 架构 | 无 `PlugIns`，主 App 单 target |
| IPA 权限 | 相机/相册英文用途说明，未申请麦克风/Siri |
| 金额 | Decimal 分位、千分位、全角测试 |
| 去重 | 第二次 commit 抛 duplicate，余额不变 |
| 撤销 | 余额恢复、session=undone、可重新导入 |
| 手续费 | 转账扣费/另付两种口径 + 撤销两账户 |
| 词库 | 瑞幸、滴滴、繁体美团等 |
| 模型不可用 | 词库兜底，不崩溃 |
| 低置信度 | `other + needsReview`，不硬猜 |

### 产物

- `LedgerBox-unsigned-0.8.0-ImageLedger.ipa`
  - 1,706,356 字节
  - SHA-256 `56F808C59F21E52A515F8FA6B944BA125828E0B6C6DD5010CAB029CC4B73D93B`
- `LedgerBox-source-0.8.0-ImageLedger.zip`
  - 大小与 SHA-256 见 `LedgerBox-0.8.0-SHA256.txt`
- `FinanceMindWeights.bin`
  - 20,971,680 字节
  - SHA-256 `506931280D71A7FC13AB7F38CEDF8CB5916D85F2BE22D3FCB4BDF3D003A320BC`

---

## 5. 未验证 / 明确没做

- 没有真机安装、签名、TestFlight/App Store 验证；
- 没有截图级 UI 视觉验收，顶栏收缩、FAB 动效、大字号/SE/Pro Max 布局需要真机看；
- 没有真实账单端到端准确率；
- 没有微信/支付宝 OAuth：缺 AppID、官方 SDK、Universal Link 和服务端 code 换 token；当前只做本地资料，不伪造授权；
- 没有 LoRA，也没有替换成 Transformer/MiniMind；
- 没有性能、内存、耗电基准；
- 没有 UI 测试；现有 52 个都是单元测试；
- 相机/相册权限弹窗、OCR 方向、真实截图质量需要真机确认。

---

## 6. P0 / P1 清单

### P0 已修

- [x] 模型生成金额/日期/订单号 → 规则层独占。
- [x] OCR 自动写账 → 草稿 + 确认。
- [x] 重复订单重复入账 → 写前 dedupe。
- [x] 订单号明文落盘 → 只存 SHA-256。
- [x] 撤销不恢复余额 → 逐条删除并回滚。
- [x] 转账手续费口径猜死 → 两种模式。
- [x] 历史写入失败留下幽灵交易 → 回滚已记录交易。
- [x] 未授权第三方登录显示“已登录” → 禁用并说明。

### P0 未完成（外部依赖）

- [ ] 真实微信/支付宝 OAuth。
- [ ] 真机相机/相册权限与 OCR 方向验收。

### P1 已修

- [x] 顶栏收缩抖动 → 8pt 阈值 + guard + 200ms。
- [x] 顶栏全宽灰条 → 移除 safe-area inset 背景。
- [x] FAB 遮挡 tab bar → 96pt padding。
- [x] 低置信度硬猜 → other + needsReview。
- [x] 多金额候选静默选择 → ambiguousAmount。
- [x] 日期缺失静默用今天 → missingDate。
- [x] 键盘遮挡金额输入 → 完成栏 + 交互式下滑。
- [x] 相机图片方向丢失 → OCR 前重绘为 upright。

### P1 待真机确认

- [ ] 所有 Tab 最后一行避让 FAB。
- [ ] 大字号、SE、Pro Max 顶栏/FAB 布局。
- [ ] 手势与滚动嵌套冲突。

---

## 7. 如何自签安装

1. 在 macOS 上用 Xcode 打开 `LedgerBox.xcodeproj`；
2. 选择 `LedgerBox` target → Signing & Capabilities；
3. 选择自己的 Team，修改 Bundle ID（如 `com.yourname.ledgerbox`）；
4. 连接 iPhone，选择真机 Run；
5. 或在 Xcode 的 Products → Archive 导出 Development IPA。

仓库不提供证书、描述文件、Team ID；未签名 IPA 不能直接安装。

---

## 8. 结论

0.8.0 的可交付核心是：

- 一条**不自动写账、可核对、可撤销**的图片记账流水线；
- 一个**不冒充生成式模型、不硬套 LoRA** 的端侧 AI 组合；
- 一个**悬浮毛玻璃顶栏 + 本地资料 + 全局 FAB** 的首页交互；
- 一份把 P0/P1、CI 结果和未验证边界写清楚的交付说明。

如果下一步要继续，我建议优先做真机视觉验收和 50–100 张真实账单的标注测试；这两项完成前，不应把“识别准确率”写进宣传。
