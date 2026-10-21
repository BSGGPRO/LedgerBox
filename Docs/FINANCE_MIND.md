# 财务专用小模型（0.3.0）

## 1. 它是什么

`FinanceMind` 是一个 **财务任务专用分类器 + 规则引擎**，不是 Qwen2.5-0.5B 裁层，也不是生成式语言模型。

```text
20 个财务意图 × 768 个字符 n-gram 哈希桶 + 20 个 bias
= 15,380 个参数
```

它做的是：

- 判断一句话属于哪类财务问题。
- 用本机账本快照和固定规则生成回答。
- 对预算、结余、储蓄率、应急金、目标进度做算术。
- 对负债、投资、保险、税务只给风险提示，不给具体买卖/申报结论。

它不做的是：

- 不生成自由文本小说。
- 不预测股票/基金涨跌。
- 不自动写账。
- 不联网。
- 不冒充 Qwen 或任何大语言模型。

## 2. 20 个意图

```text
record_expense      记支出
record_income       记收入
spending_query      查支出
balance_query       查结余/余额
budget_status       预算
category_question   分类
saving_advice       储蓄
debt_advice         负债
investment_risk     投资风险
emergency_fund      应急金
financial_goal      目标
bill_reminder       账单
subscription        订阅
impulse_spending    冲动消费
refund              退款
transfer            转账
split_bill          分账
insurance           保险
tax                 税务
other               其他
```

## 3. 回答怎么来

```text
输入文本
→ FinanceMind 意图分类
→ FinanceSnapshot（本月收入/支出/结余/余额/分类/预算/目标）
→ FinanceAdvisor 固定模板 + Decimal 计算
→ 回答卡
```

关键边界：

- 数字来自本机 Core Data，不由模型生成。
- 没有数据时说“没有数据”，不编数字。
- 回答不自动写账；写账仍走 AI 记账 / `LedgerService`。
- 回答只作记账参考，不构成投资、税务或保险建议。

## 4. 训练

脚本：

```bash
python Tools/train_finance_mind.py
```

- 语料：合成中文财务短语，按 20 个意图模板生成。
- 模型：字符 unigram + bigram，FNV-1a 哈希到 768 桶，多项逻辑回归。
- 导出：Int16 量化 + base64 内嵌 `FinanceMindWeights.swift`。
- 验证：合成验证集约 99.9%，**这个数字没有现实意义**；真实短信、方言、错别字仍需测试。

## 5. 为什么不是 Qwen2.5-0.5B

| 方案 | 体积 | 运行 | 风险 |
|---|---:|---|---|
| FinanceMind | 约 42KB 源码/权重 | 纯 Swift，毫秒级 | 只能做意图+规则，不会聊天 |
| Qwen2.5-0.5B 4-bit | 300–400MB | Core ML/llama.cpp + tokenizer + KV cache | 当前无 Mac/真机验证，首 token 慢，可能被杀 |
| 远程 Qwen API | 0MB | 需要 API Key + 网络 | 不是本地，依赖第三方 |

真正“把 Qwen 压成只懂财务”需要：

1. 教师模型推理，生成财务指令数据。
2. 结构化剪枝/蒸馏到更小学生模型。
3. 量化、Core ML 转换。
4. Mac + 真机测 tokens/s、内存、崩溃。
5. 许可证/NOTICE 处理。

当前环境做不了 1–4 的可靠验证，所以选择 **任务专用分类器 + 规则引擎**，把“财务理解”落在可审计的代码上。

## 6. 未验证

- 没有真机运行。
- 没有用真实账本做意图准确率评估。
- 没有多语言/方言测试。
- 没有税务/保险专业审校。
