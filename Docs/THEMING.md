# LedgerBox 主题与视觉规范

LedgerBox 的颜色、圆角、字号、间距集中在 `LedgerBox/Design/Theme.swift`。页面不直接写十六进制颜色，也不各自定义卡片圆角。

> 本文描述源码中的主题实现，不代表已经在 Xcode 中编译或做过视觉回归。

---

## 1. 主题架构

```text
ThemeMode        system / light / dark
ThemeAccent      blue / green / orange / red / purple
Theme            一次解析后的颜色、字号、圆角、间距
ThemeManager     ObservableObject，持久化 mode 与 accentHex
LedgerThemeKey   EnvironmentKey，默认浅色
\.ledgerTheme    EnvironmentValues 注入
```

`RootView` 读取系统 `colorScheme`，调用：

```swift
themeManager.theme(for: colorScheme)
```

然后：

```swift
.environment(\.ledgerTheme, theme)
.tint(theme.accent)
.preferredColorScheme(themeManager.preferredColorScheme)
```

页面：

```swift
@Environment(\.ledgerTheme) private var theme
```

---

## 2. 模式

| 模式 | 行为 |
|---|---|
| `system` | 跟随系统浅色/深色 |
| `light` | 强制浅色 |
| `dark` | 强制深色 |

`ThemeManager` 使用 `UserDefaults`：

```text
ledgerbox.theme.mode
ledgerbox.theme.accentHex
```

默认：

```text
mode = system
accentHex = 2F6FED
```

> `AppSettings.themeMode` / `accentColorHex` 字段存在，但当前没有与 `ThemeManager` 双向同步。主题实际以 UserDefaults 为准。

---

## 3. 强调色

| 名称 | Hex | 说明 |
|---|---|---|
| 蓝色 | `2F6FED` | 默认 |
| 绿色 | `248A5B` | 偏储蓄/收入 |
| 橙色 | `B87400` | 偏提醒 |
| 红色 | `C9454F` | 偏支出/危险 |
| 紫色 | `7B61FF` | 偏目标 |

强调色用于：

- `.tint`
- 主按钮
- 选中态
- 进度条
- 部分图标

收入/支出/警告仍使用独立的语义色，不跟随强调色。

---

## 4. 颜色令牌

### 浅色

| 令牌 | Hex | 用途 |
|---|---|---|
| `background` | `F4F5F7` | 页面背景 |
| `surface` | `FFFFFF` | 卡片 |
| `surfaceElevated` | `EDEFF3` | 次级卡片/控件底 |
| `primaryText` | `16181D` | 主文本 |
| `secondaryText` | `6C7480` | 次要文本 |
| `separator` | `E2E5EA` | 分割线 |
| `accent` | 强调色 | 主操作 |
| `onAccent` | `FFFFFF` | 强调色上的文字 |
| `income` | `248A5B` | 收入/正向 |
| `expense` | `C9454F` | 支出/负向 |
| `warning` | `B87400` | 警告/超预算 |

### 深色

| 令牌 | Hex | 用途 |
|---|---|---|
| `background` | `0E1013` | 页面背景 |
| `surface` | `181B20` | 卡片 |
| `surfaceElevated` | `22262D` | 次级卡片/控件底 |
| `primaryText` | `F5F7FA` | 主文本 |
| `secondaryText` | `A8AFBA` | 次要文本 |
| `separator` | `2C313A` | 分割线 |
| `accent` | 强调色 | 主操作 |
| `onAccent` | `FFFFFF` | 强调色上的文字 |
| `income` | `4CC38A` | 收入/正向 |
| `expense` | `F07178` | 支出/负向 |
| `warning` | `F2B84B` | 警告/超预算 |

### 使用规则

- 页面背景用 `theme.background`。
- 卡片用 `theme.surface`，卡片内次级块用 `theme.surfaceElevated`。
- 正文用 `theme.primaryText`，说明文字用 `theme.secondaryText`。
- 分割线用 `theme.separator`。
- 收入金额用 `theme.income`，支出金额用 `theme.expense`，警告用 `theme.warning`。
- 不要用纯黑/纯白硬编码。
- 不要用 `Color.red` / `Color.green` 代替语义色。

---

## 5. 间距与圆角

| 令牌 | 值 | 用途 |
|---|---:|---|
| `pagePadding` | 16 | 页面左右边距 |
| `cardPadding` | 16 | 卡片内边距 |
| `spacing` | 16 | 区块间距 |
| `smallSpacing` | 8 | 小元素间距 |
| `cardRadius` | 18 | 卡片圆角 |
| `controlRadius` | 11 | 输入框/按钮 |
| `segmentRadius` | 15 | 分段控件 |
| `iconCircleSize` | 36 | 行图标圆底 |

页面不要另造 12/14/20 等圆角；需要新层级时先在 Theme 加令牌。

---

## 6. 字体令牌

| 令牌 | 定义 | 用途 |
|---|---|---|
| `largeTitleFont` | 28 bold rounded | 页面大标题 |
| `sectionTitleFont` | 17 semibold rounded | 区块标题 |
| `bodyFont` | 15 regular | 正文 |
| `captionFont` | 12 medium | 说明/辅助 |
| `moneyFont` | 30 semibold rounded monospacedDigit | 首页余额 |
| `amountFont` | 38 semibold rounded monospacedDigit | 新增交易金额 |
| `currencySymbolFont` | 28 medium rounded | 金额符号 |
| `rowMoneyFont` | 16 semibold rounded monospacedDigit | 列表金额 |
| `headerActionFont` | 16 bold | 头部操作 |
| `buttonLabelFont` | 16 semibold rounded | 主按钮 |
| `emptyStateIconFont` | 28 medium | 空状态图标 |
| `rowIconFont` | 15 semibold | 行图标 |
| `controlIconFont` | 14 semibold | 控件图标 |
| `chartLabelFont` | 10 medium | 图表标签 |
| `badgeFont` | 10 semibold | 徽标 |

金额字体使用 `.monospacedDigit()`，避免数字跳动。

> 当前字体是固定字号，没有接入 Dynamic Type 缩放。若要做无障碍大字号，需要把 `Font.system(size:)` 改为 `@ScaledMetric` 或 `Font.custom(_:size:relativeTo:)`，并逐页回归布局。

---

## 7. 组件

### `LedgerCard`

- 使用 `theme.surface`
- `theme.cardRadius`
- `theme.cardPadding`
- 细边框 `theme.separator`

### `LedgerSectionHeader`

- 标题使用 `theme.sectionTitleFont`
- 可选右侧操作
- 与内容间距 `theme.smallSpacing`

### 空状态

- 使用 SF Symbols
- 图标圆底 `theme.surfaceElevated`
- 标题 `theme.sectionTitleFont`
- 说明 `theme.bodyFont` / `theme.secondaryText`
- 可选主按钮

### 金额

- 统一 `MoneyFormat.currency`
- 收入/支出符号与颜色分开处理
- 不用字符串拼接手写 `¥`

---

## 8. 图表配色

`StatisticsView` 使用：

- 收入柱：`theme.income`
- 支出柱：`theme.expense`
- 分类环：分类 `colorHex`，缺失时 `theme.secondaryText`
- 累计趋势：`theme.accent` + 渐变面积
- 图表轴/标签：`theme.secondaryText` / `theme.chartLabelFont`

分类颜色来自 `Category.colorHex`，不是 Theme 固定表。新增分类时需要给合法的六位十六进制值。

---

## 9. 新增颜色/令牌

步骤：

1. 在 `Theme` 增加 `let` 字段。
2. 在 `Theme.palette(for:accentHex:)` 同时提供浅色/深色值。
3. 在页面用 `theme.xxx`。
4. 在浅色/深色 Preview 中检查对比度。
5. 更新本文档。

不要：

- 在 View 中写 `Color(hex: "123456")`
- 在 View 中写 `.font(.system(size: 13))`
- 在 View 中写 `RoundedRectangle(cornerRadius: 12)`
- 用强调色替代收入/支出语义色

---

## 10. Preview 注入

页面 Preview 需要：

```swift
#Preview("浅色") {
    NavigationStack {
        SomeView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    .environmentObject(ThemeManager())
    .environment(\.ledgerTheme, Theme.palette(for: .light))
}
```

需要 `@FetchRequest` 的页面必须注入 preview context。  
需要 `@EnvironmentObject ThemeManager` 的页面必须注入 `ThemeManager()`。

当前带 `#Preview` 的文件：

- `LedgerBoxApp.swift`
- `HomeView.swift`
- `MainTabView.swift`
- `AddTransactionView.swift`
- `TransactionsView.swift`
- `StatisticsView.swift`
- `BudgetView.swift`
- `GoalsView.swift`
- `BuyCarPlanView.swift`
- `SettingsView.swift`

---

## 11. 可访问性

当前做到：

- 收入/支出同时有符号、文字和颜色，不只靠颜色。
- 金额使用等宽数字。
- 按钮有文字标签，不只靠图标。
- 图表有图例/列表文本。
- 空状态有说明文字。

尚未做：

- Dynamic Type 全量适配
- VoiceOver 全页面标签
- 高对比度模式专项
- Reduce Motion 专项
- 色盲友好配色验证

---

## 12. 已知视觉缺口

- 已有 `Assets.xcassets` 与本地生成的 AppIcon 占位；无 AccentColor asset，图标未做视觉审查。
- 无启动图资源；使用系统生成 launch screen。
- 无自定义字体文件。
- 无截图或视觉回归基线。
- `AppSettings` 主题字段与 UserDefaults 未同步。
- 固定字号，未接入 Dynamic Type。
- 图表分类颜色来自分类数据，可能出现低对比度组合。

---

## 13. 相关文档

- [`COMPONENTS.md`](COMPONENTS.md)
- [`FINANCE_RULES.md`](FINANCE_RULES.md)
- [`BUILD_STEPS.md`](BUILD_STEPS.md)
- [`WINDOWS_BUILD_SIGN.md`](WINDOWS_BUILD_SIGN.md)
- [`ACCEPTANCE.md`](ACCEPTANCE.md)
- [`../README.md`](../README.md)
