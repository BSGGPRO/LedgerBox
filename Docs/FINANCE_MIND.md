# 本地财务大脑（0.9.0）

## 1. 它是什么

`FinanceMind` 是一个 **40 类财务意图分类器 + 固定规则引擎**，不是 Qwen 裁层，也不是生成式聊天模型。

```text
40 个意图 × 1,048,576 个字符 n-gram 哈希桶 + 40 个 bias
= 41,943,080 个参数
```

权重以 Int8 存在 `LedgerBox/Resources/FinanceMindWeights.bin`，文件 **41,943,200 字节**（160 字节 Float32 bias + 41,943,040 字节 Int8 权重）。Swift 用 `Data` 映射读取，推理在本机 CPU 完成。

它做的是：

- 判断一句话属于哪类财务/记账问题。
- 只负责选择计算类型；金额、占比、预算、结余率、应急金、目标进度、现金流由 Decimal 精算引擎执行。
- 回答卡显示模型路由/规则兜底、计算类型和可复制算式。
- 覆盖个人记账和基础会计：现金流、对账、发票、报销、工资、存货、折旧、摊销、增值税、权责发生、备用金、应收应付、借款、房贷、房租、水电、医疗、教育、公益等。
- 在“财务大脑 → 大脑”里显示意图激活图、模型体检、实时探针和前 6 个概率。

它不做的是：

- 不生成自由文本小说。
- 不预测股票/基金涨跌。
- 不自动写账。
- 不联网；0.4.0 起已删除全部联网 AI 代码。
- 不冒充 Qwen 或任何大语言模型。

## 2. 40 个意图

```text
record_expense       记支出
record_income        记收入
spending_query       查支出
balance_query        查结余/余额
budget_status        预算
category_question    分类
saving_advice        储蓄
debt_advice          负债
investment_risk      投资风险
emergency_fund       应急金
financial_goal       目标
bill_reminder        账单
subscription         订阅
impulse_spending     冲动消费
refund               退款
transfer             转账
split_bill           分账
insurance            保险
tax                  税务
cashflow             现金流
reconciliation       对账
invoice              发票
reimbursement        报销
payroll              工资核算
inventory            存货
depreciation         折旧
amortization         摊销
vat                  增值税
accrual              权责发生
petty_cash           备用金
accounts_receivable  应收账款
accounts_payable     应付账款
loan                 借款
mortgage             房贷
rent                 房租
utilities            水电
medical              医疗
education            教育
charity              公益
other                其他
```

## 3. 回答怎么来

```text
输入文本
→ FinanceMind 40 类意图分类 + 8 类计算路由
→ FinanceSnapshot（本月收入/支出/结余/余额/分类/预算/目标）
→ FinanceComputeEngine：Decimal 精确执行闭集公式
→ 回答卡（模型只选公式，不生成数字）
```

关键边界：

- 数字来自本机 Core Data，由 Decimal 计算，不由模型生成。
- 没有数据时说“没有数据”，不编数字。
- 回答不自动写账；写账仍走 AI 记账 / `LedgerService`。
- 回答只作记账参考，不构成投资、税务或保险建议。

## 4. 可视化

`FinanceAdvisorView` 顶部有“对话 / 大脑”分段控件。切到“大脑”后：

- 中心显示 41,943,080 参数。
- 外圈是 40 个意图节点；当前 top 意图用强调色，其余节点按激活值着色。
- 激活图持续动画：核心呼吸、节点缓慢旋转、激活连线有脉冲流动；不需要输入也会动。
- 默认每 4.4 秒自动巡演一个问题，可在图下方暂停；手动输入会自动停止巡演。
- “模型体检”显示参数量、意图数、哈希桶、权重体积、加载状态。
- “实时探针”可输入任意短句，显示前 6 个意图概率、特征数、哈希桶数和推理耗时。
- “训练覆盖”列出全部 40 类。

激活图是 **意图激活可视化**，不是神经元级可解释性；节点大小/颜色由 Softmax 概率驱动。

## 5. 训练

脚本：

```bash
python Tools/train_finance_mind.py
```

- 语料：按 40 个意图模板生成中文财务/会计短语，并加入 50/30/20、零基预算、信封预算、债务雪球/雪崩、会计科目表、先进先出、直线法折旧等公共模板的改写短语；包含金额、账户、前缀/后缀变体。
- 特征：字符 unigram + bigram + trigram，FNV-1a 哈希到 1,048,576 桶。
- 模型：多项逻辑回归，40 × 1,048,576 权重 + 40 bias；稀疏 SGD，10 epochs。
- 量化：Int8 权重（scale 48）+ Float32 bias；导出二进制，不再把大数组塞进 Swift 源码。
- 验证：0.9.0 合成验证集 **98.3%**（2,939 条合成验证样本）；这是合成语料的回归指标，**没有现实意义**。真实短信、方言、错别字、长句仍需你自己考。
- 权重 SHA-256：`6F5E92B17EC300D7A0C69AB79324903AE4407FB992393140BB2F783B7355F380`。

## 6. 为什么不是 Qwen2.5-0.5B / MiniMind

| 方案 | 体积 | 运行 | 风险 |
|---|---:|---|---|
| FinanceMind 0.9.0 | 约 40MB 权重 | 纯 Swift，毫秒级 | 只能做意图+闭集公式路由，不会聊天 |
| Qwen2.5-0.5B 4-bit | 300–400MB | Core ML/llama.cpp + tokenizer + KV cache | 当前无 Mac/真机验证，首 token 慢，可能被杀 |
| 远程 API | 0MB | 需要 Key + 网络 | 不是本地，0.4.0 已移除 |

MiniMind 是“从零训练一个小型语言模型”的训练套装，产出的是带 tokenizer、Transformer 和 KV cache 的生成式 LLM；它和“40 类意图分类”不是同一种模型。把它塞进 App 需要 tokenizer、Transformer 推理、量化、Core ML/llama.cpp 转换和真机性能验证，体积与首 token 延迟都会明显上升。

真正“把 Qwen/MiniMind 压成只懂财务”需要教师模型蒸馏、结构化剪枝、Core ML 转换和真机性能验证；当前环境做不了这些可靠验证，所以选择 **任务专用分类器 + 规则引擎**，把“财务理解”落在可审计的代码和可检查的权重上。

## 7. 未验证

- 没有真机运行，也没有截图级视觉验收；只有 GitHub Actions 编译、归档和模拟器 XCTest。
- 没有用真实账本做意图准确率评估。
- 没有多语言/方言测试。
- 没有税务/保险专业审校。
