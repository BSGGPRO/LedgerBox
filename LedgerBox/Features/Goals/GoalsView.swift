import CoreData
import Foundation
import SwiftUI

struct GoalsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.ledgerTheme) private var theme

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \SavingsGoal.priority, ascending: true),
            NSSortDescriptor(keyPath: \SavingsGoal.createdAt, ascending: true)
        ],
        animation: .snappy
    )
    private var goals: FetchedResults<SavingsGoal>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: false)],
        animation: .snappy
    )
    private var transactions: FetchedResults<LedgerTransaction>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TemplateRules.createdAt, ascending: true)],
        animation: .snappy
    )
    private var templates: FetchedResults<TemplateRules>

    @State private var showingEditor = false
    @State private var editingGoal: SavingsGoal?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    if goals.isEmpty {
                        emptyState
                    } else {
                        summaryCard
                    }

                    if activeCarTemplate != nil {
                        buyCarEntry
                    }

                    if !goals.isEmpty {
                        ForEach(goals, id: \.objectID) { goal in
                            Button {
                                presentEditor(for: goal)
                            } label: {
                                GoalCard(
                                    goal: goal,
                                    countdown: countdown(for: goal),
                                    theme: theme
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("目标")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentEditor(for: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(theme.controlIconFont)
                    }
                    .accessibilityLabel("新增储蓄目标")
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            editingGoal = nil
        }) {
            GoalEditorView(goal: editingGoal)
                .environment(\.managedObjectContext, viewContext)
                .environment(\.ledgerTheme, theme)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var activeCarTemplate: TemplateRules? {
        templates.first {
            $0.active && $0.type == TemplateKind.car.rawValue
        }
    }

    private var buyCarEntry: some View {
        NavigationLink {
            BuyCarPlanView()
        } label: {
            LedgerCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(theme.accent.opacity(0.12))
                            .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                        Image(systemName: "car.fill")
                            .font(theme.rowIconFont)
                            .foregroundStyle(theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("买车攒钱计划")
                            .font(theme.sectionTitleFont)
                            .foregroundStyle(theme.primaryText)

                        Text("修机 4,400 → 买车 25,000 · 70/30 分账")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer(minLength: theme.smallSpacing)

                    Image(systemName: "chevron.right")
                        .font(theme.controlIconFont)
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryCard: some View {        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                HStack {
                    Text("储蓄进度")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Spacer()

                    Text("\(achievedCount) / \(goals.count) 已达成")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }

                Text("\(MoneyFormat.currency(totalCurrent)) / \(MoneyFormat.currency(totalTarget))")
                    .font(theme.moneyFont)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                ProgressView(value: summaryRatio)
                    .tint(theme.accent)

                Text(summaryMessage)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
            .animation(.snappy, value: totalCurrent)
        }
    }

    private var emptyState: some View {
        LedgerCard {
            VStack(spacing: theme.smallSpacing) {
                Image(systemName: "target")
                    .font(theme.emptyStateIconFont)
                    .foregroundStyle(theme.secondaryText)

                Text("还没有储蓄目标")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("建一个目标，填上目标金额和已存金额，LedgerBox 会根据近 30 天净结余估算完成时间。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("新增目标") {
                    presentEditor(for: nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private var achievedCount: Int {
        goals.filter { $0.goalStatus == .achieved || $0.currentValue >= $0.targetValue }.count
    }

    private var totalTarget: Decimal {
        goals.reduce(Decimal.zero) { $0 + $1.targetValue }
    }

    private var totalCurrent: Decimal {
        goals.reduce(Decimal.zero) { $0 + $1.currentValue }
    }

    /// Double is used only for the summary progress bar. [铁律2]
    private var summaryRatio: Double {
        guard totalTarget > 0 else { return 0 }
        return Swift.min(Swift.max(totalCurrent.doubleValue / totalTarget.doubleValue, 0), 1)
    }

    private var summaryMessage: String {
        let remaining = Swift.max(totalTarget - totalCurrent, Decimal.zero)
        if remaining == .zero {
            return "所有目标都已达成。"
        }
        return "所有目标还差 \(MoneyFormat.currency(remaining))"
    }

    private func countdown(for goal: SavingsGoal) -> GoalCountdown? {
        guard goal.goalStatus == .active else {
            return nil
        }

        return FinanceEngine.savingsCountdown(
            target: goal.targetValue,
            current: goal.currentValue,
            transactions: Array(transactions)
        )
    }

    private func presentEditor(for goal: SavingsGoal?) {
        editingGoal = goal
        showingEditor = true
    }
}

private struct GoalCard: View {
    let goal: SavingsGoal
    let countdown: GoalCountdown?
    let theme: Theme

    var body: some View {
        LedgerCard {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    progressRing
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(goal.name)
                                .font(theme.sectionTitleFont)
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)

                            statusBadge
                        }

                        Text("优先级 \(goal.priority)")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)

                        Text("\(MoneyFormat.currency(goal.currentValue)) / \(MoneyFormat.currency(goal.targetValue))")
                            .font(theme.rowMoneyFont)
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: theme.smallSpacing)
                }

                Divider()
                    .overlay(theme.separator)

                HStack(spacing: theme.smallSpacing) {
                    Image(systemName: "clock")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Text(countdownText)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                if let deadline = goal.deadline {
                    HStack(spacing: theme.smallSpacing) {
                        Image(systemName: "calendar")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)

                        Text("截止 \(deadline.formatted(.dateTime.year().month().day()))")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(theme.surfaceElevated, lineWidth: 8)

            Circle()
                .trim(from: 0, to: CGFloat(goal.progressRatio))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((goal.progressRatio * 100).rounded()))%")
                .font(theme.captionFont)
                .foregroundStyle(theme.primaryText)
        }
    }

    private var statusBadge: some View {
        Text(displayStatus.displayName)
            .font(theme.badgeFont)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var displayStatus: SavingsGoalStatus {
        if goal.currentValue >= goal.targetValue {
            return .achieved
        }
        return goal.goalStatus
    }

    private var ringColor: Color {
        switch displayStatus {
        case .active:
            return theme.accent
        case .achieved:
            return theme.income
        case .frozen:
            return theme.secondaryText
        }
    }

    private var statusColor: Color {
        switch displayStatus {
        case .active:
            return theme.accent
        case .achieved:
            return theme.income
        case .frozen:
            return theme.secondaryText
        }
    }

    private var countdownText: String {
        guard let countdown else {
            switch displayStatus {
            case .achieved:
                return "目标已达成，倒计时已停止。"
            case .frozen:
                return "目标已冻结，不参与倒计时。"
            case .active:
                return "等待计算。"
            }
        }

        switch countdown.status {
        case .achieved:
            return "目标已达成，倒计时已停止。"
        case .estimated(let days, let dailyRate, let activeDays):
            return "预计 \(days) 天 · 近 30 天日均 \(MoneyFormat.currency(dailyRate)) · \(activeDays) 个有效日"
        case .accumulating(let activeDays):
            return "数据积累中（\(activeDays) / 7 个有效日），暂不估算。"
        case .insufficientRate(_, let dailyRate):
            return "近 30 天日均 \(MoneyFormat.currency(dailyRate))，无法估算完成时间。"
        }
    }
}

private struct GoalEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme

    let goal: SavingsGoal?

    @State private var name: String
    @State private var targetText: String
    @State private var currentText: String
    @State private var priority: Int
    @State private var status: SavingsGoalStatus
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(goal: SavingsGoal?) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _targetText = State(initialValue: goal.map { MoneyFormat.editable($0.targetValue) } ?? "")
        _currentText = State(initialValue: goal.map { MoneyFormat.editable($0.currentValue) } ?? "0")
        _priority = State(initialValue: Int(goal?.priority ?? 1))
        _status = State(initialValue: goal?.goalStatus ?? .active)
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(
            initialValue: goal?.deadline
                ?? Calendar.current.date(byAdding: .month, value: 6, to: Date())
                ?? Date()
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    nameAndAmountCard
                    planCard

                    if goal != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(goal == nil ? "新增目标" : "编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(theme.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? theme.accent : theme.secondaryText)
                    .disabled(!canSave)
                }
            }
        }
        .tint(theme.accent)
        .presentationDragIndicator(.visible)
        .alert(
            "无法保存",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "删除这个目标？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除目标", role: .destructive) {
                deleteGoal()
            }
            Button("取消", role: .cancel) {
            }
        } message: {
            Text("删除目标不会删除任何交易，也不会改动账户余额。")
        }
    }

    private var nameAndAmountCard: some View {
        LedgerCard {
            VStack(spacing: 0) {
                HStack {
                    Text("目标名称")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    TextField("例如：换手机", text: $name)
                        .font(theme.bodyFont)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.primaryText)
                }
                .padding(.vertical, 9)

                Divider()
                    .overlay(theme.separator)

                amountRow(title: "目标金额", text: $targetText)
                    .padding(.vertical, 9)

                Divider()
                    .overlay(theme.separator)

                amountRow(title: "已存金额", text: $currentText)
                    .padding(.vertical, 9)

                Text("已存金额只用于目标进度，不会自动从账户转账。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    private var planCard: some View {
        LedgerCard {
            VStack(spacing: 0) {
                Stepper(value: $priority, in: 1...9) {
                    HStack {
                        Text("优先级")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)

                        Spacer()

                        Text("\(priority)")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .padding(.vertical, 8)

                Divider()
                    .overlay(theme.separator)

                HStack {
                    Text("状态")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Picker("状态", selection: $status) {
                        ForEach(SavingsGoalStatus.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .tint(theme.accent)
                    .fixedSize()
                }
                .padding(.vertical, 8)

                Divider()
                    .overlay(theme.separator)

                Toggle(isOn: $hasDeadline) {
                    Text("设置截止日期")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)
                }
                .tint(theme.accent)
                .padding(.vertical, 8)

                if hasDeadline {
                    DatePicker(
                        "截止日期",
                        selection: $deadline,
                        displayedComponents: .date
                    )
                    .font(theme.bodyFont)
                    .tint(theme.accent)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("删除目标", systemImage: "trash")
                .font(theme.bodyFont)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.expense)
    }

    private func amountRow(title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(theme.bodyFont)
                .foregroundStyle(theme.primaryText)

            Spacer(minLength: theme.smallSpacing)

            Text("¥")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .font(theme.rowMoneyFont)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .onChange(of: text.wrappedValue) { _, newValue in
                    sanitizeAmount(newValue, binding: text)
                }
        }
    }

    private var parsedTarget: Decimal? {
        decimal(from: targetText)
    }

    private var parsedCurrent: Decimal? {
        decimal(from: currentText)
    }

    private var canSave: Bool {
        guard
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let target = parsedTarget,
            let current = parsedCurrent
        else {
            return false
        }
        return target > 0 && current >= 0
    }

    private func decimal(from text: String) -> Decimal? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else {
            return nil
        }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func sanitizeAmount(_ rawValue: String, binding: Binding<String>) {
        var filtered = rawValue.replacingOccurrences(of: ",", with: ".")
        filtered = String(filtered.filter { $0.isNumber || $0 == "." })

        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 {
            filtered = String(parts[0]) + "." + String(parts[1])
        }

        if let dotIndex = filtered.firstIndex(of: ".") {
            let decimals = filtered.distance(
                from: filtered.index(after: dotIndex),
                to: filtered.endIndex
            )
            if decimals > 2 {
                let cutoff = filtered.index(dotIndex, offsetBy: 3)
                filtered = String(filtered[..<cutoff])
            }
        }

        if filtered != rawValue {
            binding.wrappedValue = filtered
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请输入目标名称。"
            return
        }
        guard let target = parsedTarget, target > 0 else {
            errorMessage = "目标金额必须大于 0。"
            return
        }
        guard let current = parsedCurrent, current >= 0 else {
            errorMessage = "已存金额不能小于 0。"
            return
        }

        let targetGoal = goal ?? SavingsGoal(context: viewContext)
        if goal == nil {
            targetGoal.id = UUID()
            targetGoal.createdAt = Date()
            targetGoal.templateTag = nil
        }

        targetGoal.name = trimmedName
        targetGoal.targetAmount = NSDecimalNumber(decimal: target.roundedToCents())
        targetGoal.currentAmount = NSDecimalNumber(decimal: current.roundedToCents())
        targetGoal.priority = Int16(priority)
        targetGoal.deadline = hasDeadline ? deadline : nil

        let normalizedCurrent = current.roundedToCents()
        let normalizedTarget = target.roundedToCents()
        if normalizedCurrent >= normalizedTarget {
            targetGoal.status = SavingsGoalStatus.achieved.rawValue
        } else if status == .achieved {
            targetGoal.status = SavingsGoalStatus.active.rawValue
        } else {
            targetGoal.status = status.rawValue
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteGoal() {
        guard let goal else { return }
        viewContext.delete(goal)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

#Preview("目标 · 浅色") {
    GoalsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("目标 · 深色") {
    GoalsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
