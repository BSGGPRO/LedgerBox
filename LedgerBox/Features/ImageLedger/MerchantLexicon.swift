import Foundation

/// A deterministic merchant vocabulary used when the on-device intent model is
/// unavailable or not confident. It only maps text to a display name/category;
/// it never supplies an amount, date or order ID.
struct MerchantMatch: Equatable {
    let canonical: String
    let category: LedgerCategory
    let score: Double
}

final class MerchantLexicon {

    struct Entry: Equatable {
        let canonical: String
        let aliases: [String]
        let category: LedgerCategory

        init(canonical: String, aliases: [String], category: LedgerCategory) {
            self.canonical = canonical
            self.aliases = aliases
            self.category = category
        }

        /// More than twenty everyday Chinese merchants. Aliases are matched
        /// after width/traditional normalization and punctuation folding.
        static let defaults: [Entry] = [
            Entry(
                canonical: "瑞幸咖啡",
                aliases: ["瑞幸", "瑞幸咖啡", "luckin", "luckin coffee"],
                category: .food
            ),
            Entry(
                canonical: "星巴克",
                aliases: ["星巴克", "starbucks", "starbucks coffee"],
                category: .food
            ),
            Entry(
                canonical: "麦当劳",
                aliases: ["麦当劳", "麥當勞", "mcdonald", "mcdonalds"],
                category: .food
            ),
            Entry(
                canonical: "肯德基",
                aliases: ["肯德基", "kfc", "肯德鸡"],
                category: .food
            ),
            Entry(
                canonical: "汉堡王",
                aliases: ["汉堡王", "漢堡王", "burger king"],
                category: .food
            ),
            Entry(
                canonical: "海底捞",
                aliases: ["海底捞", "海底撈", "haidilao"],
                category: .food
            ),
            Entry(
                canonical: "蜜雪冰城",
                aliases: ["蜜雪冰城", "蜜雪", "mixue"],
                category: .food
            ),
            Entry(
                canonical: "喜茶",
                aliases: ["喜茶", "heytea"],
                category: .food
            ),
            Entry(
                canonical: "奈雪的茶",
                aliases: ["奈雪的茶", "奈雪", "nayuki"],
                category: .food
            ),
            Entry(
                canonical: "库迪咖啡",
                aliases: ["库迪", "库迪咖啡", "cotti"],
                category: .food
            ),
            Entry(
                canonical: "美团",
                aliases: ["美团", "美团外卖", "美團", "美團外賣", "meituan"],
                category: .food
            ),
            Entry(
                canonical: "饿了么",
                aliases: ["饿了么", "餓了麼", "饿了么外卖", "eleme"],
                category: .food
            ),
            Entry(
                canonical: "滴滴出行",
                aliases: ["滴滴", "滴滴出行", "滴滴打车", "didi"],
                category: .transport
            ),
            Entry(
                canonical: "高德打车",
                aliases: ["高德打车", "高德", "amap"],
                category: .transport
            ),
            Entry(
                canonical: "曹操出行",
                aliases: ["曹操出行", "曹操专车", "caocao"],
                category: .transport
            ),
            Entry(
                canonical: "哈啰出行",
                aliases: ["哈啰", "哈罗", "哈啰出行", "hello bike"],
                category: .transport
            ),
            Entry(
                canonical: "中国铁路",
                aliases: ["12306", "中国铁路", "铁路12306", "中国铁路12306"],
                category: .transport
            ),
            Entry(
                canonical: "中国石化",
                aliases: ["中国石化", "中石化", "sinopec"],
                category: .transport
            ),
            Entry(
                canonical: "中国石油",
                aliases: ["中国石油", "中石油", "petrochina"],
                category: .transport
            ),
            Entry(
                canonical: "中国国航",
                aliases: ["中国国航", "国航", "air china"],
                category: .transport
            ),
            Entry(
                canonical: "淘宝",
                aliases: ["淘宝", "淘寶", "taobao"],
                category: .shopping
            ),
            Entry(
                canonical: "京东",
                aliases: ["京东", "京東", "jd", "jd.com"],
                category: .shopping
            ),
            Entry(
                canonical: "拼多多",
                aliases: ["拼多多", "pinduoduo", "pdd"],
                category: .shopping
            ),
            Entry(
                canonical: "盒马鲜生",
                aliases: ["盒马", "盒马鲜生", "盒馬", "freshippo"],
                category: .shopping
            ),
            Entry(
                canonical: "永辉超市",
                aliases: ["永辉", "永辉超市", "永輝", "yonghui"],
                category: .shopping
            ),
            Entry(
                canonical: "沃尔玛",
                aliases: ["沃尔玛", "沃爾瑪", "walmart"],
                category: .shopping
            ),
            Entry(
                canonical: "屈臣氏",
                aliases: ["屈臣氏", "watsons"],
                category: .shopping
            ),
            Entry(
                canonical: "优衣库",
                aliases: ["优衣库", "優衣庫", "uniqlo"],
                category: .shopping
            ),
            Entry(
                canonical: "7-Eleven",
                aliases: ["7-11", "711", "seven eleven", "7-eleven"],
                category: .shopping
            ),
            Entry(
                canonical: "万达影城",
                aliases: ["万达影城", "万达", "wanda"],
                category: .entertainment
            ),
            Entry(
                canonical: "猫眼电影",
                aliases: ["猫眼", "猫眼电影", "maoyan"],
                category: .entertainment
            ),
            Entry(
                canonical: "大麦网",
                aliases: ["大麦", "大麦网", "damai"],
                category: .entertainment
            ),
            Entry(
                canonical: "网易云音乐",
                aliases: ["网易云音乐", "网易云", "netEase cloud music"],
                category: .entertainment
            ),
            Entry(
                canonical: "链家",
                aliases: ["链家", "鏈家", "lianjia"],
                category: .housing
            ),
            Entry(
                canonical: "自如",
                aliases: ["自如", "ziroom"],
                category: .housing
            ),
            Entry(
                canonical: "国家电网",
                aliases: ["国家电网", "网上国网", "电费", "国网"],
                category: .housing
            ),
            Entry(
                canonical: "新东方",
                aliases: ["新东方", "新東方", "xdf"],
                category: .education
            ),
            Entry(
                canonical: "中公教育",
                aliases: ["中公教育", "中公"],
                category: .education
            ),
            Entry(
                canonical: "叮当快药",
                aliases: ["叮当快药", "叮噹快藥", "叮当"],
                category: .medical
            ),
            Entry(
                canonical: "京东健康",
                aliases: ["京东健康", "京東健康", "jd health"],
                category: .medical
            )
        ]
    }

    static let shared = MerchantLexicon()

    private struct PreparedEntry {
        let entry: Entry
        let aliasKeys: [String]
    }

    private let prepared: [PreparedEntry]

    init(entries: [Entry] = Entry.defaults) {
        prepared = entries.map { entry in
            var seen = Set<String>()
            var keys: [String] = []
            for value in [entry.canonical] + entry.aliases {
                let key = Self.fold(value)
                guard !key.isEmpty, seen.insert(key).inserted else {
                    continue
                }
                keys.append(key)
            }
            return PreparedEntry(entry: entry, aliasKeys: keys)
        }
    }

    /// Best match above the acceptance threshold, or nil when the text is not
    /// a known merchant.
    func match(_ text: String) -> MerchantMatch? {
        let haystack = Self.fold(text)
        guard haystack.count >= 2 else {
            return nil
        }

        var best: MerchantMatch?
        var bestAliasLength = 0

        for item in prepared {
            for alias in item.aliasKeys {
                guard let score = Self.score(haystack: haystack, alias: alias) else {
                    continue
                }
                let isBetter: Bool
                if let best {
                    isBetter = score > best.score
                        || (score == best.score && alias.count > bestAliasLength)
                } else {
                    isBetter = true
                }
                guard isBetter else {
                    continue
                }
                best = MerchantMatch(
                    canonical: item.entry.canonical,
                    category: item.entry.category,
                    score: score
                )
                bestAliasLength = alias.count
            }
        }

        guard let best, best.score >= 0.65 else {
            return nil
        }
        return best
    }

    // MARK: - Matching

    private static func score(haystack: String, alias: String) -> Double? {
        guard alias.count >= 2 else {
            return nil
        }

        if haystack == alias {
            return 1.0
        }

        if haystack.contains(alias) {
            // Longer aliases are more specific: "美团买药" should beat "美团".
            return 0.90 + Swift.min(Double(alias.count) / 200.0, 0.08)
        }

        let distance = bestLevenshteinDistance(
            haystack,
            alias,
            limit: 1
        )
        if distance <= 1 {
            return alias.count >= 3 ? 0.78 : 0.70
        }

        let similarity = bestJaccard(haystack, alias)
        if similarity >= 0.55 {
            return 0.60 + 0.25 * similarity
        }

        return nil
    }

    /// Folds full-width characters, common traditional variants, case and
    /// punctuation so "美團外賣", "美团外卖" and "美 团 外 卖" compare equal.
    static func fold(_ text: String) -> String {
        let normalized = ReceiptParser.normalize(text)
        let simplified = normalized.map { traditionalMap[$0] ?? $0 }
        return String(simplified)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func bestLevenshteinDistance(
        _ text: String,
        _ target: String,
        limit: Int
    ) -> Int {
        let textCharacters = Array(text)
        let targetCharacters = Array(target)
        guard !textCharacters.isEmpty, !targetCharacters.isEmpty else {
            return limit + 1
        }

        // A one-character window would make every two-character alias match
        // too broadly, so windows stay at least two characters long.
        let lower = Swift.max(2, targetCharacters.count - 1)
        let upper = Swift.min(textCharacters.count, targetCharacters.count + 1)
        guard lower <= upper else {
            return limit + 1
        }

        var best = limit + 1
        for length in lower...upper {
            for start in 0...(textCharacters.count - length) {
                let window = Array(textCharacters[start..<(start + length)])
                let distance = levenshtein(window, targetCharacters, limit: limit)
                guard distance <= limit else {
                    continue
                }
                if targetCharacters.count < 3 {
                    // Short aliases: require a shared edge character to avoid
                    // matching unrelated two-character shop names.
                    guard window.first == targetCharacters.first
                        || window.last == targetCharacters.last else {
                        continue
                    }
                }
                if distance < best {
                    best = distance
                }
            }
        }
        return best
    }

    private static func levenshtein(
        _ lhs: [Character],
        _ rhs: [Character],
        limit: Int
    ) -> Int {
        if abs(lhs.count - rhs.count) > limit {
            return limit + 1
        }

        var previous = Array(0...rhs.count)
        for (row, leftCharacter) in lhs.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: rhs.count)
            for (column, rightCharacter) in rhs.enumerated() {
                let cost = leftCharacter == rightCharacter ? 0 : 1
                current[column + 1] = Swift.min(
                    current[column] + 1,
                    Swift.min(
                        previous[column + 1] + 1,
                        previous[column] + cost
                    )
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static func bestJaccard(_ text: String, _ target: String) -> Double {
        let targetBigrams = bigrams(of: target)
        guard !targetBigrams.isEmpty else {
            return 0
        }

        let characters = Array(text)
        let targetLength = target.count
        let lower = Swift.max(2, targetLength - 1)
        let upper = Swift.min(characters.count, targetLength + 2)
        guard lower <= upper else {
            return jaccard(bigrams(of: text), targetBigrams)
        }

        var best = 0.0
        for length in lower...upper {
            for start in 0...(characters.count - length) {
                let window = String(characters[start..<(start + length)])
                let score = jaccard(bigrams(of: window), targetBigrams)
                if score > best {
                    best = score
                }
            }
        }
        return best
    }

    private static func bigrams(of value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count > 1 else {
            return Set(characters.map { String($0) })
        }
        var result = Set<String>()
        for index in 0..<(characters.count - 1) {
            result.insert(String(characters[index]) + String(characters[index + 1]))
        }
        return result
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs).count
        guard union > 0 else {
            return 0
        }
        return Double(lhs.intersection(rhs).count) / Double(union)
    }

    // MARK: - Traditional variants

    private static let traditionalMap: [Character: Character] = [
        "麥": "麦", "當": "当", "勞": "劳", "團": "团", "餓": "饿",
        "麼": "么", "龍": "龙", "鳳": "凤", "華": "华", "聯": "联",
        "電": "电", "車": "车", "號": "号", "點": "点", "飲": "饮",
        "廳": "厅", "館": "馆", "飯": "饭", "燒": "烧", "鮮": "鲜",
        "圓": "圆", "記": "记", "銀": "银", "會": "会", "員": "员",
        "買": "买", "賣": "卖", "東": "东", "寶": "宝", "貓": "猫",
        "寧": "宁", "蘇": "苏", "爾": "尔", "瑪": "玛", "麗": "丽",
        "蓮": "莲", "達": "达", "運": "运", "輸": "输", "鐵": "铁",
        "飛": "飞", "豬": "猪", "雞": "鸡", "漢": "汉", "條": "条",
        "漿": "浆", "壽": "寿", "爭": "争", "廚": "厨", "師": "师",
        "順": "顺", "豐": "丰", "灣": "湾", "臺": "台", "網": "网",
        "絡": "络", "訊": "讯", "軟": "软", "體": "体", "應": "应",
        "鋪": "铺", "樓": "楼", "層": "层", "廣": "广", "場": "场",
        "園": "园", "區": "区", "縣": "县", "鎮": "镇", "衛": "卫",
        "醫": "医", "藥": "药", "診": "诊", "療": "疗", "學": "学",
        "補": "补", "習": "习", "課": "课", "書": "书", "雜": "杂",
        "貨": "货", "萬": "万", "樂": "乐", "購": "购", "戲": "戏",
        "劇": "剧", "務": "务", "費": "费", "產": "产", "貸": "贷",
        "稅": "税", "險": "险", "財": "财", "債": "债", "儲": "储",
        "獎": "奖", "貼": "贴", "報": "报", "銷": "销", "發": "发",
        "賬": "账", "帳": "账", "單": "单", "筆": "笔", "轉": "转",
        "餘": "余", "額": "额", "總": "总", "計": "计", "實": "实",
        "時": "时", "間": "间", "後": "后", "訂": "订", "碼": "码",
        "稱": "称", "繫": "系", "價": "价", "優": "优", "現": "现",
        "掃": "扫", "盤": "盘", "鍋": "锅", "麵": "面", "饅": "馒",
        "頭": "头", "餃": "饺", "餅": "饼", "乾": "干", "淨": "净",
        "紙": "纸", "護": "护", "膚": "肤", "妝": "妆", "髮": "发",
        "鈔": "钞", "錢": "钱", "蘭": "兰", "鹹": "咸", "裡": "里",
        "為": "为", "與": "与", "這": "这", "個": "个"
    ]
}
