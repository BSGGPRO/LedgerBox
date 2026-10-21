"""Train a finance-only intent model for LedgerBox.

This is a task-specific, hashed character n-gram classifier. It is not a
compressed Qwen checkpoint and it does not generate free-form text. Use it to
route finance questions to deterministic, auditable advice templates.

Training data is synthetic. Evaluate on real phrases before trusting it.
"""

from __future__ import annotations

import base64
import random
from pathlib import Path

import numpy as np

LABELS = [
    "record_expense",
    "record_income",
    "spending_query",
    "balance_query",
    "budget_status",
    "category_question",
    "saving_advice",
    "debt_advice",
    "investment_risk",
    "emergency_fund",
    "financial_goal",
    "bill_reminder",
    "subscription",
    "impulse_spending",
    "refund",
    "transfer",
    "split_bill",
    "insurance",
    "tax",
    "other",
]
BUCKETS = 768
SCALE = 2000.0
SEED = 20261022

TEMPLATES = {
    "record_expense": [
        "微信买奶茶{amt}元",
        "午饭花了{amt}",
        "打车{amt}元",
        "超市买菜{amt}",
        "记一笔支出{amt}",
        "刚才付了{amt}",
        "淘宝买鞋{amt}",
        "交房租{amt}",
        "看电影{amt}",
        "买药{amt}",
        "加油{amt}",
        "点外卖{amt}",
        "买咖啡{amt}",
        "交电费{amt}",
    ],
    "record_income": [
        "工资到账{amt}",
        "收到红包{amt}",
        "报销到账{amt}",
        "兼职收入{amt}",
        "卖二手{amt}",
        "利息{amt}",
        "奖金{amt}",
        "老板发工资",
        "客户付款{amt}",
        "收到转账{amt}",
        "收入一笔{amt}",
        "基金分红{amt}",
        "房租收入{amt}",
        "退税到账{amt}",
    ],
    "spending_query": [
        "这个月花了多少",
        "本月支出",
        "最近消费",
        "钱都花哪了",
        "餐饮花了多少",
        "交通支出",
        "这个月外卖",
        "查一下账单",
        "上周花了多少",
        "今年总支出",
        "哪类花得最多",
        "看看消费明细",
        "本月开销",
        "花钱最多的分类",
    ],
    "balance_query": [
        "我还有多少钱",
        "账户余额",
        "这个月结余",
        "净资产多少",
        "银行卡余额",
        "现金还剩多少",
        "本月剩多少",
        "总资产",
        "可用余额",
        "收支结余",
        "查余额",
        "现在有多少钱",
    ],
    "budget_status": [
        "预算还剩多少",
        "本月预算",
        "超预算了吗",
        "餐饮预算",
        "预算用了几成",
        "还能花多少",
        "预算进度",
        "设置预算",
        "预算快超了",
        "这个月预算够吗",
        "分类预算",
        "预算提醒",
    ],
    "category_question": [
        "奶茶算哪类",
        "打车记什么分类",
        "房租属于什么",
        "工资是收入吗",
        "退款怎么分类",
        "买菜算餐饮吗",
        "加油算交通吗",
        "电影票分类",
        "医药费分类",
        "红包算收入吗",
        "转账算支出吗",
        "这个该记哪类",
    ],
    "saving_advice": [
        "怎么存钱",
        "省钱方法",
        "月光怎么办",
        "如何攒钱",
        "减少开支",
        "储蓄建议",
        "每月存多少",
        "怎么控制消费",
        "工资总是不够花",
        "想存下钱",
        "省钱技巧",
        "结余太少",
    ],
    "debt_advice": [
        "信用卡还不上",
        "花呗分期",
        "要不要贷款",
        "负债太多",
        "先还哪张卡",
        "分期划算吗",
        "网贷怎么办",
        "房贷压力",
        "车贷",
        "债务规划",
        "利息太高",
        "以贷养贷",
    ],
    "investment_risk": [
        "买基金好吗",
        "股票能买吗",
        "理财风险",
        "投资建议",
        "黄金会涨吗",
        "比特币",
        "收益高的理财",
        "基金定投",
        "炒股",
        "年化收益",
        "稳健理财",
        "投资亏了",
    ],
    "emergency_fund": [
        "应急金要多少",
        "备用金",
        "三个月生活费",
        "紧急预备金",
        "失业怎么办",
        "存多少应急",
        "家庭备用金",
        "应急储蓄",
        "六个月开支",
        "突然用钱",
    ],
    "financial_goal": [
        "想买辆车",
        "存钱买房",
        "旅行基金",
        "目标进度",
        "设置储蓄目标",
        "多久能存够",
        "买车计划",
        "年度目标",
        "攒钱买电脑",
        "目标还差多少",
        "每月存2000",
        "完成目标",
    ],
    "bill_reminder": [
        "房贷还款日",
        "信用卡账单",
        "水电费提醒",
        "下个月要交房租",
        "还款提醒",
        "账单到期",
        "固定支出",
        "自动扣款",
        "别忘了还花呗",
        "每月几号还款",
        "订阅扣费提醒",
        "账单日",
    ],
    "subscription": [
        "视频会员",
        "自动续费",
        "订阅太多",
        "取消会员",
        "音乐会员",
        "iCloud订阅",
        "健身房年卡",
        "软件订阅",
        "每月会员费",
        "连续包月",
        "会员值得吗",
        "订阅管理",
    ],
    "impulse_spending": [
        "忍不住买东西",
        "冲动消费",
        "想买但不需要",
        "直播间下单",
        "购物车",
        "报复性消费",
        "看到打折就想买",
        "控制不住手",
        "买完就后悔",
        "囤货",
        "消费冲动",
        "冷静期",
    ],
    "refund": [
        "退款到账",
        "退货",
        "淘宝退款",
        "订单取消",
        "退款算收入吗",
        "退回来的钱",
        "退款怎么记",
        "部分退款",
        "运费险",
        "退款影响预算吗",
        "原路退回",
        "退费",
    ],
    "transfer": [
        "转账给妈妈",
        "银行卡互转",
        "支付宝转微信",
        "还信用卡",
        "给朋友转钱",
        "账户之间转账",
        "转出",
        "转入",
        "还款转账",
        "转账手续费",
        "跨行转账",
        "余额宝转入",
    ],
    "split_bill": [
        "AA制",
        "和朋友吃饭分账",
        "多人聚餐",
        "帮我算每人多少",
        "分账",
        "平摊费用",
        "同事拼单",
        "旅行AA",
        "合租水电",
        "谁付了多少",
        "分账模板",
        "一起买单",
    ],
    "insurance": [
        "买保险",
        "重疾险",
        "医疗险",
        "意外险",
        "保险怎么选",
        "保费",
        "保险理赔",
        "寿险",
        "保险划算吗",
        "社保",
        "商业保险",
        "保额",
    ],
    "tax": [
        "个税",
        "报税",
        "退税",
        "专项扣除",
        "税务",
        "年终奖税",
        "发票",
        "税率",
        "补税",
        "个税APP",
        "税前税后",
        "劳务报酬税",
    ],
    "other": [
        "你好",
        "今天天气",
        "随便聊聊",
        "你是谁",
        "帮我个忙",
        "谢谢",
        "在吗",
        "测试",
        "讲个笑话",
        "这个怎么用",
        "打开设置",
        "帮助",
    ],
}

PREFIXES = ["", "请问", "帮我看看", "我想问", "这个月", "最近", "我", "能不能", "怎么", "关于"]
SUFFIXES = ["", "？", "怎么办", "可以吗", "吗", "呢"]


def fnv1a(text: str) -> int:
    value = 2166136261
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 16777619) & 0xFFFFFFFF
    return value


def buckets(text: str) -> dict[int, float]:
    chars = [
        c.lower()
        for c in text
        if not c.isdigit() and not c.isspace() and c not in "，。！？、,.!?：:；;（）()【】[]"
    ]
    out: dict[int, float] = {}
    for c in chars:
        index = fnv1a("u:" + c) % BUCKETS
        out[index] = out.get(index, 0.0) + 1.0
    for i in range(len(chars) - 1):
        index = fnv1a("b:" + chars[i] + chars[i + 1]) % BUCKETS
        out[index] = out.get(index, 0.0) + 1.0
    return out


def make_samples(rng: random.Random, repeats: int = 16) -> tuple[list[str], np.ndarray]:
    texts: list[str] = []
    labels: list[int] = []
    for label_idx, label in enumerate(LABELS):
        for _ in range(repeats):
            for template in TEMPLATES[label]:
                amount = rng.choice([
                    rng.randint(1, 99),
                    rng.randint(100, 999),
                    rng.randint(1000, 9999),
                ])
                text = template.format(amt=amount)
                text = rng.choice(PREFIXES) + text + rng.choice(SUFFIXES)
                texts.append(text)
                labels.append(label_idx)
    order = list(range(len(texts)))
    rng.shuffle(order)
    return [texts[i] for i in order], np.asarray([labels[i] for i in order], dtype=np.int64)


def main() -> None:
    rng = random.Random(SEED)
    np.random.seed(SEED)
    texts, y = make_samples(rng)
    split = int(len(texts) * 0.82)
    train_texts, valid_texts = texts[:split], texts[split:]
    train_y, valid_y = y[:split], y[split:]

    x = np.zeros((len(train_texts), BUCKETS), dtype=np.float32)
    for i, text in enumerate(train_texts):
        for index, value in buckets(text).items():
            x[i, index] = value

    classes = len(LABELS)
    w = np.zeros((classes, BUCKETS), dtype=np.float32)
    b = np.zeros(classes, dtype=np.float32)
    one_hot = np.eye(classes, dtype=np.float32)
    lr = 0.35
    batch_size = 96

    for epoch in range(26):
        order = np.random.permutation(len(train_texts))
        for start in range(0, len(order), batch_size):
            batch = order[start:start + batch_size]
            xb = x[batch]
            scores = xb @ w.T + b
            scores -= scores.max(axis=1, keepdims=True)
            probs = np.exp(scores)
            probs /= probs.sum(axis=1, keepdims=True)
            grad = (probs - one_hot[train_y[batch]]).T @ xb / len(batch)
            w -= lr * grad
            b -= lr * (probs - one_hot[train_y[batch]]).mean(axis=0)
            w *= 1.0 - lr * 2e-5

        if (epoch + 1) % 5 == 0:
            train_pred = np.argmax(x @ w.T + b, axis=1)
            print(f"epoch {epoch + 1}: train acc {(train_pred == train_y).mean():.3f}")

    xv = np.zeros((len(valid_texts), BUCKETS), dtype=np.float32)
    for i, text in enumerate(valid_texts):
        for index, value in buckets(text).items():
            xv[i, index] = value
    valid_pred = np.argmax(xv @ w.T + b, axis=1)
    print(f"valid acc {(valid_pred == valid_y).mean():.3f} / {len(valid_texts)} samples")

    wq = np.clip(np.round(w * SCALE), -32767, 32767).astype("<i2")
    bq = np.clip(np.round(b * SCALE), -32767, 32767).astype("<i2")
    raw = wq.tobytes() + bq.tobytes()
    encoded = base64.b64encode(raw).decode("ascii")
    lines = "\n".join(encoded[i:i + 120] for i in range(0, len(encoded), 120))
    labels_swift = ", ".join(f'"{label}"' for label in LABELS)

    swift = f'''import Foundation

// Generated by Tools/train_finance_mind.py. Do not edit by hand.
// {classes} finance intents x {BUCKETS} hashed character n-gram buckets + {classes} biases.
enum FinanceMindWeights {{
    static let bucketCount = {BUCKETS}
    static let classCount = {classes}
    static let scale: Float = {SCALE:.1f}
    static let labels = [{labels_swift}]

    static let encoded = """
{lines}
"""
}}
'''
    out = Path("LedgerBox/Features/QuickEntry/FinanceMindWeights.swift")
    out.write_text(swift, encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
