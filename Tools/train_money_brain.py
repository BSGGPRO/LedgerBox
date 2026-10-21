"""Train a tiny hashed character n-gram classifier for LedgerBox.

This is intentionally not an LLM. It is a ~5.6k-parameter multinomial
logistic-regression model used only as a local fallback/suggestion layer.
Training data is synthetic; evaluate on real phrases before trusting it.
"""

from __future__ import annotations

import base64
import random
from pathlib import Path

import numpy as np

LABELS = [
    "food",
    "transport",
    "shopping",
    "housing",
    "entertainment",
    "health",
    "salary",
    "investment",
    "transfer",
    "refund",
    "other",
]
BUCKETS = 512
SCALE = 2000.0
SEED = 20261021

TEMPLATES = {
    "food": [
        "午饭牛肉面{amt}元",
        "微信买奶茶{amt}元",
        "饿了么外卖{amt}元",
        "食堂吃饭{amt}元",
        "星巴克咖啡{amt}元",
        "超市买菜{amt}元",
        "火锅聚餐{amt}元",
        "早餐包子{amt}元",
        "美团点了汉堡{amt}元",
        "便利店零食{amt}元",
        "下午茶蛋糕{amt}元",
        "烧烤夜宵{amt}元",
    ],
    "transport": [
        "滴滴打车{amt}元",
        "地铁通勤{amt}元",
        "公交车费{amt}元",
        "汽车加油{amt}元",
        "高铁票{amt}元",
        "停车费{amt}元",
        "共享单车{amt}元",
        "机场大巴{amt}元",
        "打车回家{amt}元",
        "ETC过路费{amt}元",
        "电动车充电{amt}元",
        "火车票{amt}元",
    ],
    "shopping": [
        "淘宝买衣服{amt}元",
        "京东买耳机{amt}元",
        "超市日用品{amt}元",
        "拼多多纸巾{amt}元",
        "商场买鞋{amt}元",
        "网购手机壳{amt}元",
        "买洗发水{amt}元",
        "数码店买充电器{amt}元",
        "服装店买裤子{amt}元",
        "文具店买笔{amt}元",
        "家居店买收纳盒{amt}元",
        "直播间买零食{amt}元",
    ],
    "housing": [
        "房租{amt}元",
        "水费{amt}元",
        "电费{amt}元",
        "物业费{amt}元",
        "燃气费{amt}元",
        "宽带续费{amt}元",
        "房屋维修{amt}元",
        "家具配送{amt}元",
        "租房押金{amt}元",
        "小区停车月卡{amt}元",
        "家政保洁{amt}元",
        "取暖费{amt}元",
    ],
    "entertainment": [
        "电影票{amt}元",
        "游戏充值{amt}元",
        "KTV唱歌{amt}元",
        "视频会员{amt}元",
        "演唱会门票{amt}元",
        "密室逃脱{amt}元",
        "剧本杀{amt}元",
        "旅游门票{amt}元",
        "健身房月卡{amt}元",
        "音乐会员{amt}元",
        "买游戏{amt}元",
        "桌游店{amt}元",
    ],
    "health": [
        "药店买药{amt}元",
        "医院挂号{amt}元",
        "体检套餐{amt}元",
        "牙医补牙{amt}元",
        "看中医{amt}元",
        "买口罩{amt}元",
        "视力检查{amt}元",
        "住院押金{amt}元",
        "疫苗费用{amt}元",
        "按摩理疗{amt}元",
        "买维生素{amt}元",
        "急诊费{amt}元",
    ],
    "salary": [
        "工资到账{amt}元",
        "发工资{amt}元",
        "年终奖{amt}元",
        "兼职收入{amt}元",
        "报销到账{amt}元",
        "项目奖金{amt}元",
        "工资入账{amt}元",
        "劳务费{amt}元",
        "补贴到账{amt}元",
        "课时费{amt}元",
        "绩效奖金{amt}元",
        "公司打款{amt}元",
    ],
    "investment": [
        "基金收益{amt}元",
        "股票分红{amt}元",
        "银行利息{amt}元",
        "理财赎回{amt}元",
        "黄金卖出{amt}元",
        "债券利息{amt}元",
        "分红到账{amt}元",
        "投资收益{amt}元",
        "余额宝收益{amt}元",
        "定投回款{amt}元",
        "股票卖出{amt}元",
        "理财到期{amt}元",
    ],
    "transfer": [
        "转账给妈妈{amt}元",
        "银行卡转支付宝{amt}元",
        "还信用卡{amt}元",
        "给朋友转{amt}元",
        "微信转账{amt}元",
        "支付宝转银行卡{amt}元",
        "还花呗{amt}元",
        "给房东转房租{amt}元",
        "跨行转账{amt}元",
        "给同事转{amt}元",
        "还借呗{amt}元",
        "家庭账户互转{amt}元",
    ],
    "refund": [
        "退款到账{amt}元",
        "淘宝退款{amt}元",
        "退押金{amt}元",
        "退货退款{amt}元",
        "订单取消退款{amt}元",
        "携程退票{amt}元",
        "外卖退款{amt}元",
        "京东退款{amt}元",
        "酒店退订{amt}元",
        "课程退费{amt}元",
        "多付款退回{amt}元",
        "售后补偿{amt}元",
    ],
    "other": [
        "朋友还钱{amt}元",
        "收到红包{amt}元",
        "捐款{amt}元",
        "现金支出{amt}元",
        "礼金{amt}元",
        "二手卖出{amt}元",
        "罚款{amt}元",
        "丢失现金{amt}元",
        "彩票中奖{amt}元",
        "给晚辈压岁钱{amt}元",
        "收到转账{amt}元",
        "其他支出{amt}元",
    ],
}

ACCOUNTS = ["微信", "支付宝", "现金", "银行卡", "信用卡", "云闪付", "美团", "京东", "淘宝"]
PREFIXES = ["", "今天", "昨天", "刚刚", "用{acct}", "通过{acct}", "{acct}"]
SUFFIXES = ["", "，{acct}支付", "，记一下", "，谢谢", "，已付", "，到账"]


def fnv1a(text: str) -> int:
    h = 2166136261
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def buckets(text: str) -> dict[int, float]:
    normalized = "".join(
        c for c in text.lower()
        if not c.isdigit() and not c.isspace() and c not in "，。！？、,.!?：:；;（）()【】[]"
    )
    chars = list(normalized)
    out: dict[int, float] = {}
    for c in chars:
        out[fnv1a("u:" + c) % BUCKETS] = out.get(fnv1a("u:" + c) % BUCKETS, 0.0) + 1.0
    for i in range(len(chars) - 1):
        key = "b:" + chars[i] + chars[i + 1]
        h = fnv1a(key) % BUCKETS
        out[h] = out.get(h, 0.0) + 1.0
    return out


def make_samples(rng: random.Random, repeats: int = 18) -> tuple[list[str], np.ndarray]:
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
                acct = rng.choice(ACCOUNTS)
                text = template.format(amt=amount)
                text = rng.choice(PREFIXES).format(acct=acct) + text
                text += rng.choice(SUFFIXES).format(acct=acct)
                if rng.random() < 0.15:
                    text = text.replace("元", "")
                texts.append(text)
                labels.append(label_idx)
    indices = list(range(len(texts)))
    rng.shuffle(indices)
    return [texts[i] for i in indices], np.asarray([labels[i] for i in indices], dtype=np.int64)


def main() -> None:
    rng = random.Random(SEED)
    np.random.seed(SEED)
    texts, y = make_samples(rng)
    split = int(len(texts) * 0.82)
    train_texts, valid_texts = texts[:split], texts[split:]
    train_y, valid_y = y[:split], y[split:]

    x = np.zeros((len(train_texts), BUCKETS), dtype=np.float32)
    for i, text in enumerate(train_texts):
        for idx, value in buckets(text).items():
            x[i, idx] = value

    classes = len(LABELS)
    w = np.zeros((classes, BUCKETS), dtype=np.float32)
    b = np.zeros(classes, dtype=np.float32)
    lr = 0.18
    for epoch in range(28):
        order = np.random.permutation(len(train_texts))
        for i in order:
            scores = w @ x[i] + b
            scores -= scores.max()
            probs = np.exp(scores)
            probs /= probs.sum()
            probs[int(train_y[i])] -= 1.0
            w -= lr * np.outer(probs, x[i])
            b -= lr * probs
            w *= 1.0 - lr * 2e-5
        if (epoch + 1) % 7 == 0:
            pred = np.argmax(w @ x.T + b[:, None], axis=0)
            print(f"epoch {epoch + 1}: train acc {(pred == train_y).mean():.3f}")

    xv = np.zeros((len(valid_texts), BUCKETS), dtype=np.float32)
    for i, text in enumerate(valid_texts):
        for idx, value in buckets(text).items():
            xv[i, idx] = value
    pred = np.argmax(w @ xv.T + b[:, None], axis=0)
    print(f"valid acc {(pred == valid_y).mean():.3f} / {len(valid_texts)} samples")

    wq = np.clip(np.round(w * SCALE), -32767, 32767).astype("<i2")
    bq = np.clip(np.round(b * SCALE), -32767, 32767).astype("<i2")
    raw = wq.tobytes() + bq.tobytes()
    encoded = base64.b64encode(raw).decode("ascii")
    lines = "\n".join(encoded[i:i + 120] for i in range(0, len(encoded), 120))

    labels_swift = ", ".join(f'"{label}"' for label in LABELS)
    swift = f'''import Foundation

// Generated by Tools/train_money_brain.py. Do not edit by hand.
// {classes} classes x {BUCKETS} hashed character n-gram buckets + {classes} biases.
enum MoneyBrainWeights {{
    static let bucketCount = {BUCKETS}
    static let classCount = {classes}
    static let scale: Float = {SCALE:.1f}
    static let labels = [{labels_swift}]

    static let encoded = """
{lines}
"""
}}
'''
    out = Path("LedgerBox/Features/QuickEntry/MoneyBrainWeights.swift")
    out.write_text(swift, encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
