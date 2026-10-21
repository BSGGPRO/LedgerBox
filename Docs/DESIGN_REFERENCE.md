# UI 设计参考与落地

参考项目：[fchangjun/awesome-design-md-cn](https://github.com/fchangjun/awesome-design-md-cn)

这是一个中文设计系统资料库，收集了 Revolut、Wise、Apple、Stripe 等产品的 `DESIGN.md`。LedgerBox 只借鉴可复用的排版与组件原则，不复制任何产品的品牌资产、代码或页面。

## 采用的 6 条原则

1. **金融产品的克制配色**  
   近黑/白为主，收入绿、支出红只表达语义；强调色只用于主要动作和当前状态。对应 `Theme` 的 `background / surface / primaryText / income / expense / accent`。

2. **8pt 间距节奏**  
   页面 16、卡片 16–18、组件间 8、卡片圆角 20。对应 `Theme.pagePadding / cardPadding / spacing / smallSpacing / cardRadius`。

3. **胶囊按钮 + 大触控区**  
   主要动作使用 Capsule，最小高度 40–44；首页只保留底部“记一笔”，顶部不再重复加号。

4. **无阴影、靠层级和描边建立深度**  
   `LedgerCard` 使用 surface + 1px separator 描边，不堆叠阴影；深色模式用 surfaceElevated 区分层级。

5. **所有卡片同一基线**  
   两列指标卡统一 `minHeight`、顶部对齐和单行金额缩放；避免一边高一边低。统计三列也使用相同的最小高度。

6. **信息优先，动效服务于理解**  
   财务大脑的动画只表达“模型在本地运行、意图在激活”：呼吸核心、旋转节点、流动脉冲和 4.4 秒自动巡演；不遮挡文字，不伪造数据。

## 落地位置

| 原则 | 文件 |
|---|---|
| 颜色、间距、字体、卡片 | `LedgerBox/Design/Theme.swift` |
| 首页用户入口、余额与今日提示 | `LedgerBox/Features/Home/HomeView.swift` |
| 两列指标卡等高 | `FinanceAdvisorView.swift`、`FinanceBrainMapView.swift` |
| 目标完成时间 | `GoalsView.swift` |
| 预算/统计提示 | `BudgetView.swift`、`StatisticsView.swift` |
| 自动巡演与 Canvas 动画 | `FinanceBrainMapView.swift` |

## 不做的事

- 不引入第三方 UI 框架或设计系统依赖。
- 不复制 Revolut/Wise 的 Logo、插画、字体文件或页面。
- 不用动画伪造财务数字；所有金额仍来自 Core Data。
- 不为了“好看”牺牲 Dynamic Type、深色模式和可点击区域。
