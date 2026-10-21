import CoreData
import Foundation
import SwiftUI

struct BuyCarPlanView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.ledgerTheme) private var theme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TemplateRules.createdAt, ascending: true)],
        animation: .snappy
    )
    private var templates: FetchedResults<TemplateRules>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \SavingsGoal.priority, ascending: true),
            NSSortDescriptor(keyPath: \SavingsGoal.createdAt, ascending: true)
        ],
        animation: .snappy
    )
    private var goals: FetchedResults<SavingsGoal>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: false)],
        animation: .snappy
    )
    private var transactions: FetchedResults<LedgerTransaction>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var categories: FetchedResults<Category>

    @State private var sideHustleAmount = ""
    @State private var splitRatio = 0.7
    @State private var milkTeaAmount = "15"
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var carRules: BuyCarTemplateRules {
        BuyCarTemplateRules()
    }

    private var activeCarTemplate: TemplateRules? {
        templates.first {
            $0.active && $0.type == TemplateKind.car.rawValue
        }
    }

    private var cashAccount: Account? {
        accounts.first { $0.accountType == .cash }
            ?? accounts.first {
                $0.accountType != .goal && $0.accountType != .reserve
            }
    }

    private var repairAccount: Account? {
        accounts.first { $0.name == "修机专户" }
    }

    private var carAccount: Account? {
        accounts.first { $0.name == "买车专户" }
    }

    private var reserveAccount: Account? {
        accounts.first { $0.name == "备用金" }
    }

    private var repairGoal: SavingsGoal? {
        goals.first { $0.templateTag == "car.repair" }
    }

    private var carGoal: SavingsGoal? {
        goals.first { $0.templateTag == "car.car" }
    }

    private var reserveGoal: SavingsGoal? {
        goals.first { $0.templateTag == "car.reserve" }
    }

    private var isConfigured: Bool {
        activeCarTemplate != nil
            && cashAccount != nil
            && repairAccount != nil
            && carAccount != nil
            && reserveAccount != nil
    }

    private var monthInterval: DateInterval {
        FinanceEngine.interval(for: .monthly, containing: Date())
    }

    private var weekInterval: DateInterval {
        FinanceEngine.interval(for: .weekly, containing: Date())
    }

    private var monthKey: String {
        dateKey("yyyy-MM")
    }

    private var dayKey: String {
        dateKey("yyyy-MM-dd")
    }

    private var yearKey: String {
        dateKey("yyyy")
    }

    private var workTag: String {
        "car.workshift.\(dayKey)"
    }

    private var salaryTag: String {
        "car.salary.\(monthKey)"
    }

    private var surplusTag: String {
        "car.surplus.\(monthKey)"
    }

    private var hasWorkedToday: Bool {
        transactions.contains { $0.templateTag == workTag }
    }

    private var hasSalaryThisMonth: Bool {
        transactions.contains { $0.templateTag == salaryTag }
    }

    private var hasSurplusAllocationThisMonth: Bool {
        transactions.contains { $0.templateTag == surplusTag }
    }

    private var repairCurrent: Decimal {
        max(repairAccount?.balanceValue ?? repairGoal?.currentValue ?? Decimal.zero, Decimal.zero)
    }

    private var carCurrent: Decimal {
        max(carAccount?.balanceValue ?? carGoal?.currentValue ?? Decimal.zero, Decimal.zero)
    }

    private var reserveCurrent: Decimal {
        max(reserveAccount?.balanceValue ?? reserveGoal?.currentValue ?? Decimal.zero, Decimal.zero)
    }

    private var currentGoalName: String {
        if repairCurrent < BuyCarTemplateRules.repairTarget {
            return "修机专户"
        }
        if carCurrent < BuyCarTemplateRules.carTarget {
            return "买车专户"
        }
        return "备用金"
    }

    private var cashMonthNet: Decimal {
        guard let cashAccount else {
            return 0
        }
        return FinanceEngine.summary(
            transactions: Array(transactions),
            in: monthInterval,
            accountID: cashAccount.id
        ).net
    }

    private var availableSurplus: Decimal {
        guard let cashAccount else {
            return 0
        }
        let capped = min(
            max(cashMonthNet, Decimal.zero),
            max(cashAccount.balanceValue, Decimal.zero)
        )
        return capped.roundedToCents()
    }

    private var surplusPreview: (repair: Decimal, car: Decimal, overflow: Decimal) {
        carRules.allocateSurplus(
            availableSurplus,
            repairCurrent: repairCurrent,
            carCurrent: carCurrent
        )
    }

    private var splitRatioDecimal: Decimal {
        Decimal(string: String(format: "%.2f", splitRatio))
            ?? BuyCarTemplateRules.minimumSplitRatio
    }

    private var splitPercent: Int {
        Int((splitRatio * 100).rounded())
    }

    private var sideHustlePreview: (goal: Decimal, reserve: Decimal)? {
        guard let amount = parseAmount(sideHustleAmount) else {
            return nil
        }
        return carRules.splitSideHustle(amount, requestedRatio: splitRatioDecimal)
    }

    private var milkTeaCategory: Category? {
        categories.first { $0.categoryKind == .expense && $0.name == "奶茶" }
    }

    private var milkTeaMonthExpense: Decimal {
        guard let categoryID = milkTeaCategory?.id else {
            return 0
        }
        return transactions
            .filter {
                $0.transactionType == .expense
                    && $0.categoryId == categoryID
                    && monthInterval.contains($0.date)
            }
            .reduce(Decimal.zero) { $0 + $1.amountValue }
    }

    private var milkTeaWeekCups: Int {
        guard let categoryID = milkTeaCategory?.id else {
            return 0
        }
        return transactions.filter {
            $0.transactionType == .expense
                && $0.categoryId == categoryID
                && weekInterval.contains($0.date)
        }.count
    }

    private var milkTeaWarnings: [String] {
        carRules.milkTeaWarnings(
            monthExpense: milkTeaMonthExpense,
            weekCups: milkTeaWeekCups
        )
    }

    private var goalSpendingCount: Int {
        transactions.filter {
            monthInterval.contains($0.date)
                && ($0.transactionType == .expense || $0.transactionType == .transfer)
                && accountType(for: $0.accountId) == .goal
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing) {
                if isConfigured {
                    priorityCard
                    actionCard
                    surplusCard
                    milkTeaCard
                    disciplineCard
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("买车攒钱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            syncCarGoals()
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("好", role: .cancel) {
            }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Priority

    private var priorityCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("攒钱优先级")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Text(currentGoalName)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                }

                priorityRow(
                    title: "1 · 修机专户",
                    subtitle: "先补齐 4,400 元；达成后才转向买车。",
                    current: repairCurrent,
                    target: BuyCarTemplateRules.repairTarget,
                    tint: theme.accent
                )

                Divider()
                    .overlay(theme.separator)

                priorityRow(
                    title: "2 · 买车专户",
                    subtitle: "修机达成后，新增结余进入 25,000 元目标。",
                    current: carCurrent,
                    target: BuyCarTemplateRules.carTarget,
                    tint: theme.income
                )

                Divider()
                    .overlay(theme.separator)

                HStack {
                    Text("备用金 / 超额")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text(MoneyFormat.currency(reserveCurrent))
                        .font(theme.rowMoneyFont)
                        .foregroundStyle(theme.secondaryText)
                }

                Text("副业收入至少 70% 进当前目标，最多 30% 进备用金；只影响未来收入。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func priorityRow(
        title: String,
        subtitle: String,
        current: Decimal,
        target: Decimal,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: theme.smallSpacing)

                Text("\(MoneyFormat.currency(current)) / \(MoneyFormat.currency(target))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ProgressView(value: progressRatio(current, target: target))
                .tint(tint)

            Text(subtitle)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Actions

    private var actionCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("今日行动")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                actionLine(
                    icon: "clock.badge.checkmark",
                    title: "打卡上班 +100",
                    subtitle: hasWorkedToday ? "今天已经打过卡" : "每天一次，收入进入现金账户",
                    buttonTitle: hasWorkedToday ? "已打卡" : "打卡",
                    disabled: hasWorkedToday
                ) {
                    recordWorkShift()
                }

                Divider()
                    .overlay(theme.separator)

                actionLine(
                    icon: "banknote.fill",
                    title: "固定工资 +500",
                    subtitle: hasSalaryThisMonth ? "本月已经记过固定工资" : "每月一次，收入进入现金账户",
                    buttonTitle: hasSalaryThisMonth ? "已记录" : "记录",
                    disabled: hasSalaryThisMonth
                ) {
                    recordFixedSalary()
                }

                Divider()
                    .overlay(theme.separator)

                subsidyRow

                Divider()
                    .overlay(theme.separator)

                sideHustleForm
            }
        }
    }

    private func actionLine(
        icon: String,
        title: String,
        subtitle: String,
        buttonTitle: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            iconCircle(icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.primaryText)

                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: theme.smallSpacing)

            Button(action: action) {
                Text(buttonTitle)
            }
            .font(theme.captionFont)
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .disabled(disabled)
        }
    }

    private var subsidyRow: some View {
        HStack(spacing: 12) {
            iconCircle("gift.fill")

            VStack(alignment: .leading, spacing: 3) {
                Text("年度补贴")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.primaryText)

                Text("3,000 / 3,500 / 4,500 元，按年记录")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: theme.smallSpacing)

            Menu {
                ForEach(carRules.annualSubsidies(), id: \.self) { amount in
                    Button("\(amount) 元") {
                        recordSubsidy(amount)
                    }
                    .disabled(hasSubsidy(amount))
                }
            } label: {
                Text("选择")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private var sideHustleForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                iconCircle("briefcase.fill")

                VStack(alignment: .leading, spacing: 3) {
                    Text("副业收入分账")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Text("目标 \(splitPercent)% / 备用金 \(100 - splitPercent)%")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer(minLength: theme.smallSpacing)

                Text(currentGoalName)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.accent)
            }

            TextField("副业收入金额", text: $sideHustleAmount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .font(theme.bodyFont)

            Slider(value: $splitRatio, in: 0.7...1.0, step: 0.05)
                .tint(theme.accent)

            if let preview = sideHustlePreview {
                HStack {
                    Text("目标 +\(MoneyFormat.currency(preview.goal))")
                    Spacer()
                    Text("备用金 +\(MoneyFormat.currency(preview.reserve))")
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
            }

            Button("记录分账") {
                recordSideHustle()
            }
            .font(theme.buttonLabelFont)
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(sideHustlePreview == nil)

            Text("目标比例最低 70%；剩余进备用金。不会回溯已记录收入。")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Surplus

    private var surplusCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("本月结余结转")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Text(hasSurplusAllocationThisMonth ? "本月已结转" : "现金净结余")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }

                Text(MoneyFormat.currency(availableSurplus))
                    .font(theme.moneyFont)
                    .foregroundStyle(theme.primaryText)

                Text("先修机 4,400，再买车 25,000，剩余进备用金。只结转现金账户的本月净结余。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if availableSurplus > 0 && !hasSurplusAllocationThisMonth {
                    Text(
                        "预计：修机 +\(MoneyFormat.currency(surplusPreview.repair))，"
                            + "买车 +\(MoneyFormat.currency(surplusPreview.car))，"
                            + "备用金 +\(MoneyFormat.currency(surplusPreview.overflow))"
                    )
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                }

                Button("结转本月结余") {
                    recordSurplusAllocation()
                }
                .font(theme.buttonLabelFont)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(availableSurplus <= 0 || hasSurplusAllocationThisMonth)
            }
        }
    }

    // MARK: - Milk tea

    private var milkTeaCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("奶茶预算")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Text("150 元/月 · 2 杯/周")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }

                HStack {
                    Text("本月 \(MoneyFormat.currency(milkTeaMonthExpense)) / 150")
                    Spacer()
                    Text("本周 \(milkTeaWeekCups) / 2 杯")
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

                HStack(spacing: theme.smallSpacing) {
                    TextField("金额", text: $milkTeaAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .font(theme.bodyFont)

                    Button("记一杯") {
                        recordMilkTea()
                    }
                    .font(theme.captionFont)
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
                    .disabled(parseAmount(milkTeaAmount) == nil)
                }

                ForEach(milkTeaWarnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(theme.captionFont)

                        Text(warning)
                            .font(theme.captionFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(theme.warning)
                }
            }
        }
    }

    // MARK: - Discipline

    private var disciplineCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("储蓄纪律", systemImage: "shield.lefthalf.filled")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("目标专户只进不出；直接支出会触发提醒。备用金可用于应急，但也应尽量保留。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if goalSpendingCount > 0 {
                    Text("本月有 \(goalSpendingCount) 笔目标专户支出或转出，建议改为从现金账户操作。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.warning)
                }
            }
        }
    }

    private var emptyState: some View {
        LedgerCard {
            VStack(spacing: theme.smallSpacing) {
                Image(systemName: "car.fill")
                    .font(theme.emptyStateIconFont)
                    .foregroundStyle(theme.secondaryText)

                Text(activeCarTemplate == nil ? "买车模板未启用" : "买车专户不完整")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("请在首页右上角设置中启用「买车攒钱」模板。模板会创建修机专户、买车专户和备用金。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Actions

    private func recordWorkShift() {
        guard let cashAccount else {
            showAlert(title: "缺少账户", message: "请先启用买车模板。")
            return
        }

        let draft = LedgerDraft(
            type: .income,
            amount: carRules.workShiftIncome(),
            date: Date(),
            note: "打卡上班",
            account: cashAccount,
            category: incomeCategory(named: "工资"),
            templateTag: workTag
        )

        do {
            try LedgerService.recordBatch([draft], in: viewContext)
            showAlert(title: "已打卡", message: "100 元已进入现金账户。")
        } catch {
            showAlert(title: "打卡失败", message: error.localizedDescription)
        }
    }

    private func recordFixedSalary() {
        guard let cashAccount else {
            showAlert(title: "缺少账户", message: "请先启用买车模板。")
            return
        }

        let draft = LedgerDraft(
            type: .income,
            amount: carRules.fixedMonthlyIncome(),
            date: Date(),
            note: "固定工资",
            account: cashAccount,
            category: incomeCategory(named: "工资"),
            templateTag: salaryTag
        )

        do {
            try LedgerService.recordBatch([draft], in: viewContext)
            showAlert(title: "已记录", message: "固定工资 500 元已进入现金账户。")
        } catch {
            showAlert(title: "记录失败", message: error.localizedDescription)
        }
    }

    private func recordSubsidy(_ amount: Decimal) {
        guard let cashAccount else {
            showAlert(title: "缺少账户", message: "请先启用买车模板。")
            return
        }

        let tag = "car.subsidy.\(yearKey).\(amount)"
        guard !transactions.contains(where: { $0.templateTag == tag }) else {
            showAlert(title: "已领取", message: "本年度这笔补贴已经记录。")
            return
        }

        let draft = LedgerDraft(
            type: .income,
            amount: amount,
            date: Date(),
            note: "年度补贴",
            account: cashAccount,
            category: incomeCategory(named: "工资"),
            templateTag: tag
        )

        do {
            try LedgerService.recordBatch([draft], in: viewContext)
            showAlert(title: "已记录", message: "\(MoneyFormat.currency(amount)) 补贴已进入现金账户。")
        } catch {
            showAlert(title: "记录失败", message: error.localizedDescription)
        }
    }

    private func recordSideHustle() {
        guard
            let amount = parseAmount(sideHustleAmount),
            let repairAccount,
            let carAccount,
            let reserveAccount
        else {
            showAlert(title: "无法分账", message: "请填写有效金额，并确认买车模板已启用。")
            return
        }

        let split = carRules.splitSideHustle(amount, requestedRatio: splitRatioDecimal)
        let allocation = carRules.allocateSurplus(
            split.goal,
            repairCurrent: repairCurrent,
            carCurrent: carCurrent
        )
        let reserveTotal = split.reserve + allocation.overflow
        var drafts: [LedgerDraft] = []

        if allocation.repair > 0 {
            drafts.append(
                LedgerDraft(
                    type: .income,
                    amount: allocation.repair,
                    date: Date(),
                    note: "副业收入 · 修机专户",
                    account: repairAccount,
                    category: incomeCategory(named: "副业"),
                    templateTag: "car.side.\(monthKey).repair"
                )
            )
        }

        if allocation.car > 0 {
            drafts.append(
                LedgerDraft(
                    type: .income,
                    amount: allocation.car,
                    date: Date(),
                    note: "副业收入 · 买车专户",
                    account: carAccount,
                    category: incomeCategory(named: "副业"),
                    templateTag: "car.side.\(monthKey).car"
                )
            )
        }

        if reserveTotal > 0 {
            drafts.append(
                LedgerDraft(
                    type: .income,
                    amount: reserveTotal,
                    date: Date(),
                    note: "副业收入 · 备用金",
                    account: reserveAccount,
                    category: incomeCategory(named: "副业"),
                    templateTag: "car.side.\(monthKey).reserve"
                )
            )
        }

        guard !drafts.isEmpty else {
            showAlert(title: "金额过小", message: "分账后没有可记录的正数金额。")
            return
        }

        do {
            try LedgerService.recordBatch(drafts, in: viewContext)
            let synced = syncCarGoals()
            sideHustleAmount = ""
            if synced {
                showAlert(
                    title: "分账完成",
                    message: "修机 +\(MoneyFormat.currency(allocation.repair))，"
                        + "买车 +\(MoneyFormat.currency(allocation.car))，"
                        + "备用金 +\(MoneyFormat.currency(reserveTotal))。"
                )
            }
        } catch {
            showAlert(title: "分账失败", message: error.localizedDescription)
        }
    }

    private func recordSurplusAllocation() {
        guard
            let cashAccount,
            let repairAccount,
            let carAccount,
            let reserveAccount
        else {
            showAlert(title: "缺少账户", message: "请先启用买车模板。")
            return
        }

        guard !hasSurplusAllocationThisMonth else {
            showAlert(title: "本月已结转", message: "同一个月份只结转一次，避免重复入账。")
            return
        }

        let surplus = availableSurplus
        guard surplus > 0 else {
            showAlert(title: "没有可结转结余", message: "本月现金账户净结余为 0 或负数。")
            return
        }

        let allocation = carRules.allocateSurplus(
            surplus,
            repairCurrent: repairCurrent,
            carCurrent: carCurrent
        )

        var drafts: [LedgerDraft] = []

        if allocation.repair > 0 {
            drafts.append(
                LedgerDraft(
                    type: .transfer,
                    amount: allocation.repair,
                    date: Date(),
                    note: "结余结转 · 修机专户",
                    account: cashAccount,
                    toAccount: repairAccount,
                    templateTag: surplusTag
                )
            )
        }

        if allocation.car > 0 {
            drafts.append(
                LedgerDraft(
                    type: .transfer,
                    amount: allocation.car,
                    date: Date(),
                    note: "结余结转 · 买车专户",
                    account: cashAccount,
                    toAccount: carAccount,
                    templateTag: surplusTag
                )
            )
        }

        if allocation.overflow > 0 {
            drafts.append(
                LedgerDraft(
                    type: .transfer,
                    amount: allocation.overflow,
                    date: Date(),
                    note: "结余结转 · 备用金",
                    account: cashAccount,
                    toAccount: reserveAccount,
                    templateTag: surplusTag
                )
            )
        }

        guard !drafts.isEmpty else {
            showAlert(title: "无需结转", message: "所有目标都已达成，且没有可分配金额。")
            return
        }

        do {
            try LedgerService.recordBatch(drafts, in: viewContext)
            let synced = syncCarGoals()
            if synced {
                showAlert(
                    title: "已结转",
                    message: "修机 +\(MoneyFormat.currency(allocation.repair))，"
                        + "买车 +\(MoneyFormat.currency(allocation.car))，"
                        + "备用金 +\(MoneyFormat.currency(allocation.overflow))。"
                )
            }
        } catch {
            showAlert(title: "结转失败", message: error.localizedDescription)
        }
    }

    private func recordMilkTea() {
        guard let amount = parseAmount(milkTeaAmount), let cashAccount else {
            showAlert(title: "无法记录", message: "请填写有效金额，并确认现金账户存在。")
            return
        }

        let draft = LedgerDraft(
            type: .expense,
            amount: amount,
            date: Date(),
            note: "奶茶",
            account: cashAccount,
            category: milkTeaCategory,
            templateTag: "car.milktea"
        )

        do {
            try LedgerService.recordBatch([draft], in: viewContext)
            showAlert(title: "已记录奶茶", message: "\(MoneyFormat.currency(amount)) 已从现金账户支出。")
        } catch {
            showAlert(title: "记录失败", message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func syncCarGoals() -> Bool {
        var changed = false

        for goal in goals {
            guard goal.goalStatus != .frozen,
                  let tag = goal.templateTag,
                  tag.hasPrefix("car."),
                  let account = accountForGoal(goal)
            else {
                continue
            }

            let current = max(account.balanceValue, Decimal.zero).roundedToCents()
            if goal.currentValue != current {
                goal.currentAmount = NSDecimalNumber(decimal: current)
                changed = true
            }

            let expectedStatus: SavingsGoalStatus = current >= goal.targetValue
                ? .achieved
                : .active
            if goal.goalStatus != expectedStatus {
                goal.status = expectedStatus.rawValue
                changed = true
            }
        }

        guard changed else {
            return true
        }

        do {
            try viewContext.save()
            return true
        } catch {
            viewContext.rollback()
            showAlert(title: "同步失败", message: error.localizedDescription)
            return false
        }
    }

    private func accountForGoal(_ goal: SavingsGoal) -> Account? {
        guard let tag = goal.templateTag else {
            return accounts.first { $0.name == goal.name }
        }

        switch tag {
        case "car.repair":
            return repairAccount
        case "car.car":
            return carAccount
        case "car.reserve":
            return reserveAccount
        default:
            return accounts.first { $0.name == goal.name }
        }
    }

    private func accountType(for accountID: UUID) -> AccountType? {
        accounts.first { $0.id == accountID }?.accountType
    }

    private func incomeCategory(named name: String) -> Category? {
        categories.first { $0.categoryKind == .income && $0.name == name }
    }

    private func hasSubsidy(_ amount: Decimal) -> Bool {
        transactions.contains {
            $0.templateTag == "car.subsidy.\(yearKey).\(amount)"
        }
    }

    private func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: cleaned), value > 0 else {
            return nil
        }
        let rounded = value.roundedToCents()
        return rounded > 0 ? rounded : nil
    }

    private func progressRatio(_ current: Decimal, target: Decimal) -> Double {
        guard target > 0 else {
            return 0
        }
        let ratio = (current / target).doubleValue
        return min(max(ratio, 0), 1)
    }

    private func dateKey(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }

    private func iconCircle(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(theme.surfaceElevated)
                .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

            Image(systemName: systemName)
                .font(theme.rowIconFont)
                .foregroundStyle(theme.accent)
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

#Preview("买车 · 浅色") {
    BuyCarPlanView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("买车 · 深色") {
    BuyCarPlanView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
