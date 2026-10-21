"""Train LedgerBox's local finance-intent model.

This is a hashed character n-gram linear classifier, not a compressed LLM.
It routes a phrase to one of 40 accounting intents; advice text is deterministic.

Parameters: 40 x 1,048,576 weights + 40 biases = 41,943,080.
The exported weights are Int8 (about 40 MB), loaded from the app bundle.

Training data is synthetic. The validation number is synthetic-only and must not
be presented as real-world accuracy.
"""

from __future__ import annotations

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
    "cashflow",
    "reconciliation",
    "invoice",
    "reimbursement",
    "payroll",
    "inventory",
    "depreciation",
    "amortization",
    "vat",
    "accrual",
    "petty_cash",
    "accounts_receivable",
    "accounts_payable",
    "loan",
    "mortgage",
    "rent",
    "utilities",
    "medical",
    "education",
    "charity",
    "other",
]

BUCKETS = 1_048_576
SCALE = 48.0
SEED = 20261021
EPOCHS = 10
REPEATS = 22
LR = 0.34

TEMPLATES: dict[str, list[str]] = {
    "record_expense": [
        "微信买奶茶{amt}元", "午饭花了{amt}", "打车{amt}元", "超市买菜{amt}",
        "记一笔支出{amt}", "刚才付了{amt}", "淘宝买鞋{amt}", "看电影{amt}",
        "买咖啡{amt}", "点外卖{amt}", "加油{amt}", "买了一件衣服{amt}",
        "支付宝付款{amt}", "现金支出{amt}", "今天消费{amt}", "买书{amt}",
        "充话费{amt}", "交停车费{amt}", "买水果{amt}", "修手机{amt}",
        "这个物品是口红但是口红价格是1000元", "我买了一台电动车花费22000", "买了一个东西花{amt}",
    ],
    "record_income": [
        "工资到账{amt}", "收到红包{amt}", "兼职收入{amt}", "卖二手{amt}",
        "利息收入{amt}", "奖金到账{amt}", "老板发工资", "客户付款{amt}",
        "收入一笔{amt}", "基金分红{amt}", "房租收入{amt}", "退税到账{amt}",
        "稿费{amt}", "直播打赏{amt}", "收款{amt}", "副业赚了{amt}",
        "收到转账{amt}", "红包收入{amt}", "退货赔款{amt}", "平台补贴{amt}",
    ],
    "spending_query": [
        "这个月花了多少", "本月支出", "最近消费", "钱都花哪了",
        "餐饮花了多少", "交通支出", "这个月外卖", "查一下账单",
        "上周花了多少", "今年总支出", "哪类花得最多", "看看消费明细",
        "本月开销", "花钱最多的分类", "上个月支出", "每天平均花多少",
        "最近三个月消费趋势", "这个月超支了吗", "支出明细", "查消费记录",
    ],
    "balance_query": [
        "我还有多少钱", "账户余额", "这个月结余", "净资产多少",
        "银行卡余额", "现金还剩多少", "本月剩多少", "总资产",
        "可用余额", "收支结余", "查余额", "现在有多少钱",
        "支付宝余额", "微信余额", "所有账户加起来", "负债和资产",
        "这个月存下多少", "现金流余额", "账户总览", "余额对不对",
    ],
    "budget_status": [
        "预算还剩多少", "本月预算", "超预算了吗", "餐饮预算",
        "预算用了几成", "还能花多少", "预算进度", "设置预算",
        "预算快超了", "这个月预算够吗", "分类预算", "预算提醒",
        "预算执行率", "剩余额度", "预算调整", "月度预算",
        "周预算", "预算超支", "预算分配", "预算怎么设",
    ],
    "category_question": [
        "奶茶算哪类", "打车记什么分类", "房租属于什么", "工资是收入吗",
        "退款怎么分类", "买菜算餐饮吗", "加油算交通吗", "电影票分类",
        "医药费分类", "红包算收入吗", "转账算支出吗", "这个该记哪类",
        "水电费算什么", "学费记什么", "保险算哪类", "捐款怎么分类",
        "利息记收入还是支出", "装修算哪类", "宠物花销分类", "数码产品分类",
    ],
    "saving_advice": [
        "怎么存钱", "省钱方法", "月光怎么办", "如何攒钱",
        "减少开支", "储蓄建议", "每月存多少", "怎么控制消费",
        "工资总是不够花", "想存下钱", "省钱技巧", "结余太少",
        "存钱计划", "强制储蓄", "先存后花", "储蓄率怎么提高",
        "每月固定存钱", "攒钱方法", "消费降级", "预算内生活",
    ],
    "debt_advice": [
        "信用卡还不上", "花呗分期", "要不要贷款", "负债太多",
        "先还哪张卡", "分期划算吗", "网贷怎么办", "房贷压力",
        "车贷", "债务规划", "利息太高", "以贷养贷",
        "信用卡最低还款", "负债率", "先还高息还是低息", "债务雪球",
        "债务雪崩", "逾期怎么办", "协商还款", "提前还贷划算吗",
    ],
    "investment_risk": [
        "买基金好吗", "股票能买吗", "理财风险", "投资建议",
        "黄金会涨吗", "比特币", "收益高的理财", "基金定投",
        "炒股", "年化收益", "稳健理财", "投资亏了",
        "资产配置", "股票仓位", "指数基金", "债券基金",
        "风险承受能力", "投资组合", "止盈止损", "理财诈骗",
    ],
    "emergency_fund": [
        "应急金要多少", "备用金", "三个月生活费", "紧急预备金",
        "失业怎么办", "存多少应急", "家庭备用金", "应急储蓄",
        "六个月开支", "突然用钱", "应急资金放哪", "裁员准备",
        "医疗急用钱", "家庭风险准备", "现金储备", "安全垫",
        "几个月的生活费", "应急账户", "突发支出", "流动性准备",
    ],
    "financial_goal": [
        "想买辆车", "存钱买房", "旅行基金", "目标进度",
        "设置储蓄目标", "多久能存够", "买车计划", "年度目标",
        "攒钱买电脑", "目标还差多少", "每月存2000", "完成目标",
        "结婚基金", "装修基金", "养老金目标", "教育金目标",
        "首付目标", "目标倒计时", "目标金额", "储蓄目标进度",
    ],
    "bill_reminder": [
        "房贷还款日", "信用卡账单", "水电费提醒", "下个月要交房租",
        "还款提醒", "账单到期", "固定支出", "自动扣款",
        "别忘了还花呗", "每月几号还款", "订阅扣费提醒", "账单日",
        "还款计划", "到期提醒", "信用卡还款", "花呗还款",
        "白条还款", "账单日历", "固定账单", "扣款失败",
    ],
    "subscription": [
        "视频会员", "自动续费", "订阅太多", "取消会员",
        "音乐会员", "iCloud订阅", "健身房年卡", "软件订阅",
        "每月会员费", "连续包月", "会员值得吗", "订阅管理",
        "网盘会员", "视频平台年卡", "自动扣费", "试用期结束",
        "家庭共享订阅", "订阅清理", "会员涨价", "取消自动续费",
    ],
    "impulse_spending": [
        "忍不住买东西", "冲动消费", "想买但不需要", "直播间下单",
        "购物车", "报复性消费", "看到打折就想买", "控制不住手",
        "买完就后悔", "囤货", "消费冲动", "冷静期",
        "限时折扣", "凑单", "种草", "拔草",
        "情绪消费", "深夜下单", "重复购买", "购物上瘾",
        "今天怎样避免乱花钱", "怎么才能不乱花钱", "不要乱花钱", "控制消费欲望",
    ],
    "refund": [
        "退款到账", "退货", "淘宝退款", "订单取消",
        "退款算收入吗", "退回来的钱", "退款怎么记", "部分退款",
        "运费险", "退款影响预算吗", "原路退回", "退费",
        "退款冲减支出", "售后赔款", "取消订单", "退款到银行卡",
        "退款和收入区别", "退款记账", "退货退款", "服务退款",
    ],
    "transfer": [
        "转账给妈妈", "银行卡互转", "支付宝转微信", "还信用卡",
        "给朋友转钱", "账户之间转账", "转出", "转入",
        "还款转账", "转账手续费", "跨行转账", "余额宝转入",
        "内部转账", "账户搬家", "从工资卡转生活费", "还花呗",
        "信用卡还款算转账吗", "转账不算支出", "自己账户互转", "转错账",
    ],
    "split_bill": [
        "AA制", "和朋友吃饭分账", "多人聚餐", "帮我算每人多少",
        "分账", "平摊费用", "同事拼单", "旅行AA",
        "合租水电", "谁付了多少", "分账模板", "一起买单",
        "三个人怎么分", "有人不喝酒怎么分", "垫付后怎么分", "群收款",
        "拼车费用", "合租账单", "分账记账", "共同支出",
    ],
    "insurance": [
        "买保险", "重疾险", "医疗险", "意外险",
        "保险怎么选", "保费", "保险理赔", "寿险",
        "保险划算吗", "社保", "商业保险", "保额",
        "免赔额", "等待期", "续保", "保险缴费",
        "保险记账", "车险", "家财险", "保险退保",
    ],
    "tax": [
        "个税", "报税", "退税", "专项扣除",
        "税务", "年终奖税", "税率", "补税",
        "个税APP", "税前税后", "劳务报酬税", "个税汇算",
        "专项附加扣除", "税务规划", "个税申报", "稿酬所得",
        "经营所得", "税务风险", "完税证明", "税收优惠",
    ],
    "cashflow": [
        "现金流怎么样", "经营现金流", "现金流入流出", "现金流分析",
        "现金流表", "自由现金流", "现金流紧张", "现金流预测",
        "这个月现金流", "现金缺口", "现金流管理", "现金流入",
        "现金流出", "现金流断裂", "经营性现金流", "投资现金流",
        "筹资现金流", "现金流健康吗", "现金余额变化", "现金流规划",
    ],
    "reconciliation": [
        "怎么对账", "银行对账", "账实不符", "对账差异",
        "余额调节表", "对账单", "账目对不上", "核对流水",
        "微信账单对账", "支付宝对账", "信用卡对账", "库存对账",
        "往来对账", "对账流程", "未达账项", "对账调整",
        "账本和银行不一致", "月末对账", "对账差额", "自动对账",
    ],
    "invoice": [
        "发票怎么开", "开票", "进项发票", "销项发票",
        "发票抬头", "发票税号", "电子发票", "发票报销",
        "发票丢失", "红字发票", "发票认证", "发票管理",
        "增值税发票", "普通发票", "专用发票", "发票入账",
        "发票查验", "无票支出", "发票归档", "发票备注",
    ],
    "reimbursement": [
        "报销怎么记", "差旅报销", "垫付报销", "费用报销",
        "公司报销", "报销单", "报销流程", "报销到账",
        "员工报销", "业务招待费", "交通报销", "住宿报销",
        "报销凭证", "报销额度", "报销审批", "个人垫付",
        "报销和收入区别", "报销冲减支出", "报销被打回", "报销明细",
        "报销怎么记账", "费用报销怎么记", "员工报销怎么记",
        "差旅费报销怎么记", "报销单怎么填", "公司报销流程",
        "报销到账怎么记", "垫付报销怎么记", "报销冲减什么",
        "报销和工资区别", "招待费报销", "打车报销",
        "出差住宿报销", "报销科目", "报销附件", "报销标准",
    ],
    "payroll": [
        "工资核算", "计提工资", "代扣个税", "社保公积金",
        "发工资", "工资表", "应发工资", "实发工资",
        "五险一金", "工资分录", "绩效工资", "加班费",
        "年终奖核算", "离职结算", "工资条", "个税代扣",
        "工资成本", "劳务费", "临时工工资", "工资发放",
    ],
    "inventory": [
        "存货怎么记", "库存商品", "进货", "结转成本",
        "库存盘点", "存货跌价", "原材料", "在途物资",
        "库存周转", "先进先出", "加权平均", "存货成本",
        "库存数量", "仓库台账", "商品入库", "商品出库",
        "存货周转率", "积压库存", "盘盈盘亏", "库存管理",
    ],
    "depreciation": [
        "折旧怎么算", "固定资产折旧", "残值", "折旧年限",
        "直线法折旧", "加速折旧", "设备折旧", "车辆折旧",
        "房屋折旧", "折旧分录", "累计折旧", "固定资产清理",
        "折旧政策", "月折旧额", "折旧抵税", "折旧与摊销区别",
        "固定资产入账", "资产减值", "折旧表", "折旧影响利润",
    ],
    "amortization": [
        "摊销怎么记", "长期待摊费用", "无形资产摊销", "摊销年限",
        "开办费摊销", "装修费摊销", "软件摊销", "土地使用权摊销",
        "摊销分录", "直线法摊销", "摊销表", "待摊费用",
        "预付费用摊销", "摊销与折旧", "摊销影响利润", "无形资产",
        "特许权摊销", "租赁改良摊销", "摊销政策", "月摊销额",
    ],
    "vat": [
        "增值税怎么算", "进项税", "销项税", "增值税税率",
        "一般纳税人", "小规模纳税人", "增值税申报", "进项抵扣",
        "销项税额", "进项税额", "增值税发票", "附加税",
        "增值税分录", "留抵税额", "简易计税", "差额征税",
        "增值税负率", "价税分离", "含税价", "不含税价",
    ],
    "accrual": [
        "权责发生制", "收付实现制", "应计费用", "预提费用",
        "权责发生制和收付实现制区别", "应计收入", "预收账款",
        "待摊费用", "计提费用", "费用归属期", "跨期费用",
        "收入确认", "配比原则", "会计分期", "应计制",
        "现金制", "预提所得税", "期末计提", "权责发生",
        "收入和费用匹配", "记账基础",
    ],
    "petty_cash": [
        "备用金怎么管", "零用金", "现金盘点", "备用金报销",
        "备用金制度", "定额备用金", "备用金补足", "现金日记账",
        "库存现金", "现金短缺", "现金溢余", "备用金借出",
        "备用金归还", "小额支出", "现金管理", "备用金限额",
        "出纳备用金", "现金清查", "现金收支", "备用金台账",
    ],
    "accounts_receivable": [
        "应收账款", "客户欠款", "赊销", "回款",
        "应收账款周转", "坏账准备", "账龄分析", "催款",
        "应收票据", "预收账款", "客户对账", "销售挂账",
        "应收款管理", "回款计划", "逾期应收", "坏账核销",
        "应收账款分录", "合同资产", "应收余额", "客户信用",
    ],
    "accounts_payable": [
        "应付账款", "供应商欠款", "赊购", "付款计划",
        "应付票据", "预付款", "供应商对账", "采购挂账",
        "应付款管理", "付款审批", "账期", "到期付款",
        "应付账款分录", "暂估入账", "供应商信用", "付款排期",
        "应付余额", "采购发票", "三单匹配", "欠供应商钱",
    ],
    "loan": [
        "借款怎么记", "贷款记账", "短期借款", "长期借款",
        "利息支出", "还本付息", "借款利息", "贷款利息",
        "银行贷款", "民间借款", "借款合同", "借款费用",
        "本金和利息", "提前还款", "贷款手续费", "借款分录",
        "资金占用费", "贷款利率", "等额本息", "等额本金",
    ],
    "mortgage": [
        "房贷怎么记", "按揭贷款", "月供", "房贷利息",
        "首付", "房贷提前还款", "公积金贷款", "商业贷款",
        "房贷利率", "按揭分录", "房子月供", "房贷压力",
        "贷款买房", "房贷还款", "房贷计算", "首套房",
        "二套房", "LPR", "房贷期限", "房贷预算",
    ],
    "rent": [
        "房租怎么记", "交房租", "租金", "押金",
        "房东", "租房合同", "房租分摊", "办公室租金",
        "商铺租金", "租金收入", "租金支出", "预付房租",
        "房租押金退还", "合租房租", "月租", "年付房租",
        "租金发票", "租赁负债", "房租预算", "租房成本",
    ],
    "utilities": [
        "水电费怎么记", "电费", "水费", "燃气费",
        "物业费", "宽带费", "取暖费", "水电燃气",
        "公共事业费", "电费分摊", "合租水电", "充电费",
        "电话费", "网费", "垃圾处理费", "能源费",
        "水电费预算", "缴费提醒", "水电账单", "费用分摊",
    ],
    "medical": [
        "看病怎么记", "挂号费", "药费", "住院费",
        "医保报销到账", "医保能报多少", "医保报销比例",
        "体检费", "牙科费用", "手术费",
        "医疗支出", "门诊费", "药店买药", "医疗险理赔",
        "大病支出", "医疗预算", "健康支出", "康复费用",
        "心理咨询", "眼科配镜", "疫苗费用", "急诊费用",
        "看病花了一万", "医院缴费", "住院押金", "医保卡余额",
    ],
    "education": [
        "学费怎么记", "培训班", "书本费", "考试报名费",
        "教育支出", "孩子学费", "网课", "证书考试",
        "留学费用", "幼儿园学费", "辅导班", "学习资料",
        "教育金", "培训预算", "技能课程", "驾校学费",
        "学校餐费", "住宿费", "研学费", "知识付费",
    ],
    "charity": [
        "捐款怎么记", "慈善捐赠", "公益捐款", "捐物",
        "水滴筹", "爱心捐赠", "捐赠支出", "公益组织",
        "捐赠发票", "慈善抵税", "志愿者", "助学捐款",
        "救灾捐款", "捐书", "捐赠预算", "公益项目",
        "捐赠凭证", "企业捐赠", "个人捐赠", "爱心基金",
    ],
    "other": [
        "你好", "今天天气", "随便聊聊", "你是谁",
        "帮我个忙", "谢谢", "在吗", "测试",
        "讲个笑话", "这个怎么用", "打开设置", "帮助",
        "今天吃什么", "推荐一部电影", "翻译一下", "写一首诗",
        "现在几点", "你叫什么", "怎么用手机", "无聊",
    ],
}

# Common public budgeting / accounting templates, rewritten as short Chinese
# phrases. These are generic methods (50/30/20, zero-based budget, debt snowball,
# chart of accounts, straight-line depreciation, etc.), not copied app data.
TEMPLATE_PACK: dict[str, list[str]] = {
    "record_expense": [
        "早餐包子豆浆{amt}", "地铁公交{amt}", "停车费{amt}", "洗衣液{amt}",
        "宠物粮{amt}", "感冒药{amt}", "话费充值{amt}", "电费{amt}",
        "水费{amt}", "燃气费{amt}", "物业费{amt}", "快递费{amt}",
    ],
    "record_income": [
        "工资条实发{amt}", "项目尾款{amt}", "稿费到账{amt}", "公积金提取{amt}",
        "保险理赔{amt}", "平台结算{amt}", "利息到账{amt}", "年终奖{amt}",
    ],
    "spending_query": [
        "餐饮占多少", "这个月哪类花最多", "通勤花了多少", "订阅一年多少钱",
        "上月结余", "本月消费结构", "固定支出有多少", "可选支出有多少",
    ],
    "balance_query": [
        "可用资金", "资产减负债", "余额宝还有多少", "信用卡欠多少",
        "净资产", "所有账户余额", "这个月还剩多少",
    ],
    "budget_status": [
        "50/30/20预算", "零基预算怎么分", "信封预算法", "预算滚动",
        "预算剩余天数", "预算执行到哪了", "预算需要调整吗",
    ],
    "category_question": [
        "早餐算餐饮吗", "宠物医院算哪类", "份子钱算哪类", "装修材料算哪类",
        "年费算订阅吗", "停车费算交通吗", "体检算医疗吗",
    ],
    "saving_advice": [
        "50/30/20法则", "储蓄率20%", "先支付自己", "自动转存",
        "零钱储蓄", "365天存钱法", "工资一到先存钱", "把储蓄当固定支出",
    ],
    "debt_advice": [
        "债务雪球法", "债务雪崩法", "负债率多少安全", "信用卡分期真实利率",
        "债务整合", "最低还款陷阱", "先还高息债务", "债务清单",
    ],
    "investment_risk": [
        "指数基金定投", "资产配置60/40", "风险测评", "不要追涨杀跌",
        "投资时钟", "分散投资", "长期持有", "本金安全",
    ],
    "emergency_fund": [
        "3到6个月生活费", "应急金放货币基金", "家庭现金流断裂",
        "应急金覆盖房租", "失业储备金", "应急金不要拿去投资",
    ],
    "financial_goal": [
        "SMART目标", "目标拆成月度", "里程碑", "预计达成日期",
        "首付还差多少", "目标每月存多少", "目标进度落后吗",
    ],
    "bill_reminder": [
        "账单日还款日", "自动扣款失败", "年费提醒", "房租到期",
        "还款日快到了", "固定扣款清单", "账单逾期",
    ],
    "subscription": [
        "订阅审计", "年付还是月付", "家庭共享", "免费试用",
        "会员自动续费", "订阅清单", "取消不用的会员",
    ],
    "impulse_spending": [
        "24小时冷静期", "购物清单", "想要和需要", "直播带货",
        "限时秒杀", "凑满减", "先放购物车", "不买立省",
    ],
    "refund": [
        "退款原路返回", "退款冲减预算", "部分退款", "退款到账时间",
        "退款影响统计吗", "退货运费谁出",
    ],
    "transfer": [
        "自己账户互转", "还信用卡不算支出", "跨行手续费",
        "工资卡转生活费", "余额宝转出", "账户内部调拨",
    ],
    "split_bill": [
        "AA制怎么算", "三个人平分", "垫付报销", "群收款",
        "合租账单", "按人头分", "有人不吃怎么分",
    ],
    "insurance": [
        "百万医疗险", "重疾保额", "免赔额一万", "等待期90天",
        "社保和商保", "保险受益人", "续保条件",
    ],
    "tax": [
        "个税专项附加扣除", "汇算清缴", "劳务报酬预扣", "个体户核定征收",
        "个税年度汇算", "专项扣除怎么填", "补税还是退税",
    ],
    "cashflow": [
        "直接法现金流", "间接法现金流", "经营活动现金流", "自由现金流",
        "现金流入流出表", "现金流缺口", "现金流预测",
    ],
    "reconciliation": [
        "银行余额调节表", "未达账项", "账实相符", "对账差异",
        "月末结账", "流水核对", "账本和银行不一致",
    ],
    "invoice": [
        "专票普票", "三流一致", "进项转出", "电子发票查重",
        "发票抬头税号", "开票资料", "红字发票",
    ],
    "reimbursement": [
        "报销单", "差旅报销", "费用归属", "发票抬头",
        "报销标准", "垫付报销", "报销进度",
    ],
    "payroll": [
        "五险一金", "实发工资", "个税代扣", "工资分摊",
        "工资表", "社保基数", "公积金基数",
    ],
    "inventory": [
        "先进先出", "加权平均", "存货盘点", "跌价准备",
        "库存周转", "期末存货", "存货成本",
    ],
    "depreciation": [
        "直线法折旧", "双倍余额递减", "残值率", "固定资产卡片",
        "折旧年限", "月折旧额", "已提折旧",
    ],
    "amortization": [
        "长期待摊费用", "摊销期限", "无形资产摊销",
        "装修费摊销", "待摊费用", "每月摊销额",
    ],
    "vat": [
        "进项税额", "销项税额", "增值税税率", "留抵退税",
        "进项抵扣", "销项减进项", "小规模纳税人",
    ],
    "accrual": [
        "权责发生制", "收付实现制", "预提费用", "待摊费用",
        "期末结转", "收入确认", "费用配比",
    ],
    "petty_cash": [
        "备用金定额", "报销补足", "备用金盘点",
        "备用金限额", "零星支出", "备用金日记账",
    ],
    "accounts_receivable": [
        "应收账款账龄", "信用期", "坏账准备", "催收",
        "客户欠款", "应收周转", "账龄分析",
    ],
    "accounts_payable": [
        "应付账款周转", "供应商账期", "付款计划",
        "应付余额", "采购欠款", "付款优先级",
    ],
    "loan": [
        "等额本息", "等额本金", "提前还款违约金", "LPR",
        "借款利率", "月供计算", "利息总额",
    ],
    "mortgage": [
        "房贷利率", "等额本息", "等额本金", "月供",
        "首付比例", "贷款年限", "提前还房贷",
    ],
    "rent": [
        "押一付三", "房租摊销", "二房东", "房租押金",
        "租房合同", "每月房租", "房租涨价",
    ],
    "utilities": [
        "阶梯电价", "水费燃气费", "物业费", "取暖费",
        "电费账单", "水电分摊", "公共能耗",
    ],
    "medical": [
        "医保起付线", "封顶线", "自费药", "住院押金",
        "医保目录", "门诊报销", "大病保险",
    ],
    "education": [
        "教育金", "学费摊销", "培训班退费",
        "教育储蓄", "学期学费", "课外班预算",
    ],
    "charity": [
        "公益捐赠票据", "捐赠税前扣除", "慈善组织",
        "定向捐赠", "物资捐赠", "志愿服务",
    ],
    "other": [
        "今天星期几", "推荐餐厅", "讲个故事", "附近有什么好玩的",
        "现在几点", "帮我写句话", "今天天气怎么样",
    ],
}

for _label, _phrases in TEMPLATE_PACK.items():
    TEMPLATES[_label].extend(_phrases)


PREFIXES = ["", "请问", "帮我看看", "我想问", "这个月", "最近", "我", "能不能", "怎么", "关于", "公司", "家里"]
SUFFIXES = ["", "？", "怎么办", "可以吗", "吗", "呢", "怎么记账", "怎么处理"]
ACCOUNTS = ["微信", "支付宝", "银行卡", "现金", "信用卡", "公司账户", "个人账户", ""]


def fnv1a(text: str) -> int:
    value = 2166136261
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 16777619) & 0xFFFFFFFF
    return value


def features(text: str) -> dict[int, float]:
    chars = [
        c.lower()
        for c in text
        if not c.isdigit() and not c.isspace() and c not in "，。！？、,.!?：:；;（）()【】[]《》“”\"'"
    ]
    out: dict[int, float] = {}
    for c in chars:
        index = fnv1a("u:" + c) % BUCKETS
        out[index] = out.get(index, 0.0) + 1.0
    for i in range(len(chars) - 1):
        index = fnv1a("b:" + chars[i] + chars[i + 1]) % BUCKETS
        out[index] = out.get(index, 0.0) + 1.0
    for i in range(len(chars) - 2):
        index = fnv1a("t:" + chars[i] + chars[i + 1] + chars[i + 2]) % BUCKETS
        out[index] = out.get(index, 0.0) + 1.0
    return out


def make_samples(rng: random.Random) -> tuple[list[str], np.ndarray]:
    texts: list[str] = []
    labels: list[int] = []
    for label_idx, label in enumerate(LABELS):
        seeds = TEMPLATES[label]
        for _ in range(REPEATS):
            for template in seeds:
                amount = rng.choice([
                    rng.randint(1, 99),
                    rng.randint(100, 999),
                    rng.randint(1000, 9999),
                    rng.randint(10000, 99999),
                ])
                text = template.format(amt=amount)
                prefix = rng.choice(PREFIXES)
                suffix = rng.choice(SUFFIXES)
                account = rng.choice(ACCOUNTS)
                # Keep "other" natural; finance examples can carry an account prefix.
                if label == "other":
                    text = f"{prefix}{text}{suffix}"
                else:
                    text = f"{account}{prefix}{text}{suffix}"
                texts.append(text)
                labels.append(label_idx)
    order = list(range(len(texts)))
    rng.shuffle(order)
    return [texts[i] for i in order], np.asarray([labels[i] for i in order], dtype=np.int64)


def softmax(scores: np.ndarray) -> np.ndarray:
    shifted = scores - scores.max()
    values = np.exp(shifted)
    return values / values.sum()


def evaluate(weights: np.ndarray, bias: np.ndarray, texts: list[str], labels: np.ndarray) -> float:
    correct = 0
    for text, label in zip(texts, labels):
        scores = bias.copy()
        for bucket, value in features(text).items():
            scores += weights[:, bucket] * value
        if int(scores.argmax()) == int(label):
            correct += 1
    return correct / max(1, len(texts))


def main() -> None:
    rng = random.Random(SEED)
    np.random.seed(SEED)
    texts, y = make_samples(rng)
    split = int(len(texts) * 0.88)
    train_texts, valid_texts = texts[:split], texts[split:]
    train_y, valid_y = y[:split], y[split:]

    # Cache sparse features; 40 x 524,288 weights stay dense (about 84 MB).
    train_features = [features(text) for text in train_texts]
    classes = len(LABELS)
    weights = np.zeros((classes, BUCKETS), dtype=np.float32)
    bias = np.zeros(classes, dtype=np.float32)

    for epoch in range(EPOCHS):
        order = np.random.permutation(len(train_texts))
        # A small amount of L2 is applied once per epoch, not per sample.
        weights *= 0.99995
        for i in order:
            feats = train_features[int(i)]
            scores = bias.copy()
            for bucket, value in feats.items():
                scores += weights[:, bucket] * value
            probs = softmax(scores)
            grad = probs
            grad[int(train_y[i])] -= 1.0
            for bucket, value in feats.items():
                weights[:, bucket] -= LR * grad * value
            bias -= LR * grad
        if (epoch + 1) % 2 == 0:
            train_pred = evaluate(weights, bias, train_texts[:3000], train_y[:3000])
            print(f"epoch {epoch + 1}: sampled train acc {train_pred:.3f}")

    valid_acc = evaluate(weights, bias, valid_texts, valid_y)
    train_acc = evaluate(weights, bias, train_texts[:5000], train_y[:5000])
    print(f"synthetic train acc {train_acc:.3f} / {min(5000, len(train_texts))} samples")
    print(f"synthetic valid acc {valid_acc:.3f} / {len(valid_texts)} samples")

    max_weight = float(np.abs(weights).max())
    clip_ratio = float(np.mean(np.abs(weights) * SCALE > 127))
    print(f"max weight {max_weight:.3f}, clip ratio {clip_ratio:.6f}")
    if clip_ratio > 0.0001:
        raise SystemExit("quantization clips too much; lower SCALE")

    wq = np.clip(np.round(weights * SCALE), -127, 127).astype(np.int8)
    bias_bytes = np.asarray(bias, dtype="<f4").tobytes()
    raw = bias_bytes + wq.tobytes(order="C")

    resource = Path("LedgerBox/Resources/FinanceMindWeights.bin")
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_bytes(raw)
    print(f"wrote {resource} ({resource.stat().st_size} bytes)")

    labels_swift = ",\n        ".join(f'"{label}"' for label in LABELS)
    swift = f'''import Foundation

// Generated by Tools/train_finance_mind.py. Do not edit by hand.
// {classes} finance intents x {BUCKETS} hashed character n-gram buckets + {classes} biases.
// Int8 weights are stored in FinanceMindWeights.bin; this file only holds metadata.
enum FinanceMindWeights {{
    static let bucketCount = {BUCKETS}
    static let classCount = {classes}
    static let scale: Float = {SCALE:.1f}
    static let parameterCount = bucketCount * classCount + classCount
    static let weightByteCount = bucketCount * classCount
    static let biasByteCount = classCount * MemoryLayout<Float>.size
    static let labels = [
        {labels_swift}
    ]
}}
'''
    out = Path("LedgerBox/Features/QuickEntry/FinanceMindWeights.swift")
    out.write_text(swift, encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
