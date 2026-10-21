import SwiftUI

struct FinanceExchange: Identifiable {
    let id = UUID()
    let question: String
    let advice: FinanceAdvice
    var localNarration: String?
}

struct FinanceAdvisorView: View {
    private enum Mode: String, CaseIterable {
        case chat = "对话"
        case brain = "大脑"
    }

    @Environment(\.ledgerTheme) private var theme
    @State private var mode: Mode = .chat
    @StateObject private var localModel = QwenLocalModel.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: false)]
    ) private var transactions: FetchedResults<LedgerTransaction>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true)]
    ) private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)]
    ) private var categories: FetchedResults<Category>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Budget.startDate, ascending: false)]
    ) private var budgets: FetchedResults<Budget>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SavingsGoal.createdAt, ascending: false)]
    ) private var goals: FetchedResults<SavingsGoal>

    @State private var input = ""
    @State private var exchanges: [FinanceExchange] = []
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private let prompts = [
        "这个月花在哪了？",
        "预算还剩多少？",
        "怎么存钱？",
        "奶茶算哪类？",
        "要不要分期？"
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: theme.spacing) {
                    heroCard
                    modePicker

                    if mode == .chat {
                        snapshotGrid
                        coachCard

                        if exchanges.isEmpty {
                            introCard
                            promptChips
                        } else {
                            ForEach(exchanges) { exchange in
                                exchangeCard(exchange)
                                    .id(exchange.id)
                            }
                        }
                    } else {
                        FinanceBrainMapView()
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
                .keyboardDismissOnBlankTap { inputFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
            // Only the chat composer owns this bar; in "大脑" mode
            // FinanceBrainMapView contributes its own, and two accessory bars
            // would show two "完成" buttons.
            .keyboardDoneBar(isEnabled: mode == .chat) { inputFocused = false }
            .onChange(of: exchanges.count) { _, _ in
                if let last = exchanges.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("财务大脑")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            localModel.prepare()
        }
        .safeAreaInset(edge: .bottom) {
            if mode == .chat {
                composer
            }
        }
        .alert(
            "财务大脑",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var heroCard: some View {
        LedgerCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [theme.accent.opacity(0.22), theme.accent.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "brain.head.profile")
                        .font(theme.rowIconFont)
                        .foregroundStyle(theme.accentText)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("财务专用小模型")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Text("41,943,080 参数 · 本地 · 40 类记账意图")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)

                    Text("解释层 · \(localModel.status.summary)")
                        .font(theme.badgeFont)
                        .foregroundStyle(
                            localModel.isReady ? theme.income : theme.secondaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                Text("离线")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.income)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.income.opacity(0.12), in: Capsule())
            }
        }
    }

    private var modePicker: some View {
        Picker("视图", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var snapshotGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCard(title: "本月收入", value: MoneyFormat.currency(snapshot.monthIncome), icon: "arrow.down.left", color: theme.income)
            metricCard(title: "本月支出", value: MoneyFormat.currency(snapshot.monthExpense), icon: "arrow.up.right", color: theme.expense)
            metricCard(title: "本月结余", value: MoneyFormat.currency(snapshot.monthNet), icon: "equal", color: theme.accentText)
            metricCard(title: "账户总余额", value: MoneyFormat.currency(snapshot.totalBalance), icon: "banknote", color: theme.primaryText)
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(theme.badgeFont)
                        .foregroundStyle(color)
                    Text(title)
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                }

                Text(value)
                    .font(theme.moneyFont)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        }
    }

    private var coachCard: some View {
        CoachTipCard(
            tip: FinanceCoach.dailyTip(
                context: FinanceCoachContext(
                    monthIncome: snapshot.monthIncome,
                    monthExpense: snapshot.monthExpense,
                    totalBalance: snapshot.totalBalance,
                    budgetLimit: snapshot.budgetLimit,
                    budgetSpent: snapshot.budgetSpent,
                    goalName: snapshot.goalName,
                    goalTarget: snapshot.goalTarget,
                    goalCurrent: snapshot.goalCurrent,
                    topCategory: snapshot.categories.first?.name,
                    topCategoryAmount: snapshot.categories.first?.amount,
                    transactionCount: transactions.filter {
                        FinanceEngine.interval(for: .monthly, containing: Date()).contains($0.date)
                    }.count
                )
            ),
            compact: true
        )
    }

    private var introCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("问它财务问题")
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.primaryText)

                Text("它先把问题分到 40 个记账/财务意图，再由本地 Decimal 精算引擎算出金额、占比、预算和现金流；模型只选公式，不生成数字。切到“大脑”能看到 4194 万参数的本地激活图。不会编数字，不会自动写账。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var promptChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        ask(prompt)
                    } label: {
                        Text(prompt)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func exchangeCard(_ exchange: FinanceExchange) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(exchange.question)
                .font(theme.bodyFont)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            LedgerCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exchange.advice.title)
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.primaryText)

                        Spacer(minLength: 4)

                        Text(exchange.advice.tag)
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.accentText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.1), in: Capsule())
                    }

                    Text(exchange.advice.body)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let narration = exchange.localNarration {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("0.5B 本地解释")
                                .font(theme.badgeFont.weight(.semibold))
                                .foregroundStyle(theme.accentText)

                            Text(narration)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            theme.accent.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }

                    if let calculation = exchange.advice.calculation {
                        Rectangle()
                            .fill(theme.separator)
                            .frame(height: 1)

                        HStack(spacing: 6) {
                            Image(systemName: calculation.kind.symbolName)
                                .font(theme.badgeFont)
                                .foregroundStyle(theme.accentText)

                            Text(calculation.kind.displayName)
                                .font(theme.badgeFont.weight(.semibold))
                                .foregroundStyle(theme.accentText)

                            Spacer(minLength: 4)

                            Text(calculation.routedByModel ? "模型路由" : "规则兜底")
                                .font(theme.badgeFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Text(calculation.formula)
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    Text("只作记账参考，不构成投资/税务建议")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("问支出、预算、储蓄、负债…", text: $input, axis: .vertical)
                .focused($inputFocused)
                .font(theme.bodyFont)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                )

            Button {
                ask(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(theme.headerActionFont)
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("提问")
        }
        .padding(.horizontal, theme.pagePadding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return
        }

        input = ""
        inputFocused = false
        let advice = FinanceAdvisor.answer(to: question, snapshot: snapshot)
        let exchange = FinanceExchange(question: question, advice: advice)
        exchanges.append(exchange)

        guard localModel.isReady else { return }
        Task {
            guard let narration = await localModel.narrate(
                question: question,
                advice: advice
            ) else {
                return
            }
            guard let index = exchanges.firstIndex(where: { $0.id == exchange.id }) else {
                return
            }
            exchanges[index].localNarration = narration
        }
    }

    private var snapshot: FinanceSnapshot {
        let interval = FinanceEngine.interval(for: .monthly, containing: Date())
        let summary = FinanceEngine.summary(transactions: Array(transactions), in: interval)

        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var spending: [String: Decimal] = [:]
        for transaction in transactions where interval.contains(transaction.date) {
            guard let categoryID = transaction.categoryId,
                  let name = categoryNames[categoryID] else {
                continue
            }
            switch transaction.transactionType {
            case .expense:
                spending[name, default: 0] += transaction.amountValue
            case .refund:
                spending[name, default: 0] -= transaction.amountValue
            case .income, .transfer:
                break
            }
        }

        let categories = spending
            .filter { $0.value > 0 }
            .map { (name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        let totalBalance = accounts.reduce(Decimal.zero) { $0 + $1.balanceValue }

        let monthlyBudgets = budgets.filter { $0.enabled && $0.budgetPeriod == .monthly }
        let totalBudget = monthlyBudgets.first { $0.categoryId == nil }
        let budgetLimit: Decimal?
        let budgetSpent: Decimal?
        if let totalBudget {
            budgetLimit = totalBudget.limitValue
            budgetSpent = summary.expense
        } else if !monthlyBudgets.isEmpty {
            budgetLimit = monthlyBudgets.reduce(Decimal.zero) { $0 + $1.limitValue }
            budgetSpent = monthlyBudgets.reduce(Decimal.zero) { partial, budget in
                guard let categoryID = budget.categoryId,
                      let name = categoryNames[categoryID] else {
                    return partial
                }
                return partial + (spending[name] ?? 0)
            }
        } else {
            budgetLimit = nil
            budgetSpent = nil
        }

        let goal = goals.first { $0.goalStatus == .active }
        return FinanceSnapshot(
            monthIncome: summary.income,
            monthExpense: summary.expense,
            totalBalance: totalBalance,
            categories: categories,
            budgetLimit: budgetLimit,
            budgetSpent: budgetSpent,
            goalName: goal?.name,
            goalTarget: goal?.targetValue,
            goalCurrent: goal?.currentValue
        )
    }
}
