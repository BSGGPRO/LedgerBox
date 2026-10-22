import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct FinanceExchange: Identifiable {
    let id = UUID()
    let question: String
    let advice: FinanceAdvice
    var localNarration: String?
}

/// Per-message action state. `confirmation` is the routing result plus the
/// confirm/undo flags; `parsed` is the QuickEntryParser output for record
/// actions and stays nil for export/backup/image.
private struct FinanceActionCardState {
    var confirmation: AIActionConfirmation
    var parsed: QuickEntryParser.ParsedEntry?
    var failure: String?
    var notice: String?
    var importSessionIDs: [UUID] = []
}

private enum FinanceAdvisorSheet: String, Identifiable {
    case image

    var id: String { rawValue }
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

    @Environment(\.managedObjectContext) private var viewContext

    @State private var input = ""
    @State private var exchanges: [FinanceExchange] = []
    @State private var errorMessage: String?
    @State private var actionCards: [UUID: FinanceActionCardState] = [:]
    @State private var activeSheet: FinanceAdvisorSheet?
    @State private var showingExporter = false
    @State private var csvText = ""
    @State private var exportFilename = "LedgerBox"
    @State private var exportExchangeID: UUID?
    @State private var showingBackupExporter = false
    @State private var backupData = Data()
    @State private var backupFilename = "LedgerBox-backup"
    @State private var backupExchangeID: UUID?
    @State private var imageFlowExchangeID: UUID?
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
                        coreRouteCard
                        engineStatusCard
                        introCard

                        if !exchanges.isEmpty {
                            chatTranscriptHeader

                            ForEach(exchanges) { exchange in
                                exchangeCard(exchange)
                                    .id(exchange.id)
                            }
                        }

                        promptChips
                            .id("finance-chat-end")
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
                guard !exchanges.isEmpty else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo("finance-chat-end", anchor: .bottom)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .image:
                ImageLedgerFlowView { sessions in
                    imageImportDidCommit(sessions)
                }
                .environment(\.managedObjectContext, viewContext)
                .environment(\.ledgerTheme, theme)
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(text: csvText),
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                finishExport(error: nil)
            case .failure(let error):
                finishExport(error: error)
            }
        }
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: JSONBackupDocument(data: backupData),
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                finishBackupExport(error: nil)
            case .failure(let error):
                finishBackupExport(error: error)
            }
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

    private var coreRouteCard: some View {
        LedgerCard {
            HStack(alignment: .center, spacing: 12) {
                LedgerIconBadge(
                    systemName: "point.3.connected.trianglepath.dotted",
                    tint: theme.accentText,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("核心路由")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("40 个财务/会计意图 · 41,943,080 参数 · Decimal 精算")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button {
                    mode = .chat
                    inputFocused = true
                } label: {
                    Text("对话")
                        .font(theme.badgeFont.weight(.semibold))
                        .foregroundStyle(theme.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开下方对话输入框")
            }
        }
    }

    private var engineStatusCard: some View {
        LedgerCard {
            HStack(alignment: .center, spacing: 12) {
                LedgerIconBadge(
                    systemName: "cpu",
                    tint: localModel.status.isReady ? theme.income : theme.warning,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("本地解释引擎")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text("Qwen2.5-0.5B-Instruct · \(localModel.status.summary)")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Text(localModel.status.isReady ? "已加载" : "未就绪")
                    .font(theme.badgeFont.weight(.semibold))
                    .foregroundStyle(
                        localModel.status.isReady ? theme.income : theme.warning
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        (localModel.status.isReady ? theme.income : theme.warning)
                            .opacity(0.12),
                        in: Capsule()
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "本地解释引擎，Qwen2.5-0.5B-Instruct，\(localModel.status.summary)"
        )
    }

    private var chatTranscriptHeader: some View {
        HStack {
            Text("对话记录")
                .font(theme.overlineFont)
                .tracking(0.8)
                .foregroundStyle(theme.secondaryText)

            Spacer(minLength: 4)

            Text("\(exchanges.count) 轮")
                .font(theme.badgeFont)
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(.horizontal, 2)
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
        VStack(alignment: .leading, spacing: 7) {
            Text("快捷提问")
                .font(theme.overlineFont)
                .tracking(0.8)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 2)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            input = prompt
                            inputFocused = true
                        } label: {
                            Text(prompt)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(theme.surface, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            theme.separator,
                                            lineWidth: theme.hairline
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("填入下方输入框")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
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

                    if let card = actionCards[exchange.id] {
                        actionSection(exchangeID: exchange.id, card: card)
                    }

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
            Button {
                activeSheet = .image
            } label: {
                Image(systemName: "plus")
                    .font(theme.headerActionFont)
                    .foregroundStyle(theme.accentText)
                    .frame(width: 40, height: 40)
                    .background(theme.surfaceElevated, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.borderStrong.opacity(0.45), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上传图片记账")

            TextField("问点什么财务问题…", text: $input, axis: .vertical)
                .focused($inputFocused)
                .font(theme.bodyFont)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                        .strokeBorder(theme.separator, lineWidth: theme.hairline)
                }

            Button {
                ask(input)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(theme.headerActionFont)
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("发送问题")
        }
        .padding(.horizontal, theme.pagePadding)
        .padding(.vertical, 10)
        .background(theme.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.5)
        }
    }

    private func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            return
        }

        input = ""
        inputFocused = false
        let routed = AIActionRouter.route(question)

        switch routed.intent {
        case .query, .unknown:
            // Existing behaviour: the deterministic advisor answers and the
            // 0.5B model only narrates. Nothing is written.
            let advice = FinanceAdvisor.answer(to: question, snapshot: snapshot)
            let exchange = FinanceExchange(question: question, advice: advice)
            exchanges.append(exchange)
            narrate(question: question, advice: advice, exchangeID: exchange.id)

        case .record:
            presentRecordAction(question: question, routed: routed)

        case .exportCSV, .backupJSON, .imageImport:
            presentConfirmedAction(question: question, routed: routed)
        }
    }

    private func narrate(question: String, advice: FinanceAdvice, exchangeID: UUID) {
        guard localModel.isReady else { return }
        Task {
            guard let narration = await localModel.narrate(
                question: question,
                advice: advice
            ) else {
                return
            }
            guard let index = exchanges.firstIndex(where: { $0.id == exchangeID }) else {
                return
            }
            exchanges[index].localNarration = narration
        }
    }

    // MARK: - Action routing

    private var parserCategoryOptions: [QuickEntryParser.CategoryOption] {
        categories
            .filter { $0.isSelectable }
            .map {
                QuickEntryParser.CategoryOption(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.categoryKind
                )
            }
    }

    private var parserAccountOptions: [QuickEntryParser.AccountOption] {
        accounts.map {
            QuickEntryParser.AccountOption(id: $0.id, name: $0.name)
        }
    }

    private func presentRecordAction(question: String, routed: AIRoutedAction) {
        let source = routed.recordText ?? question
        let parsed = QuickEntryParser().parse(
            source,
            categories: parserCategoryOptions,
            accounts: parserAccountOptions
        )
        let exchange = FinanceExchange(
            question: question,
            advice: recordAdvice(for: parsed)
        )
        exchanges.append(exchange)
        actionCards[exchange.id] = FinanceActionCardState(
            confirmation: AIActionConfirmation(action: routed),
            parsed: parsed,
            failure: nil,
            notice: nil
        )
    }

    private func recordAdvice(for parsed: QuickEntryParser.ParsedEntry) -> FinanceAdvice {
        guard parsed.isReadyToSave else {
            let missing = missingLabels(for: parsed)
            let detail = missing.isEmpty
                ? "解析结果不完整，先不写账。可以补充金额、分类或账户后再试。"
                : "还缺：\(missing.joined(separator: "、"))。补全后才会写账，现在没有保存任何内容。"
            return FinanceAdvice(title: "这笔还差信息", body: detail, tag: "未入账")
        }

        return FinanceAdvice(
            title: "准备记一笔",
            body: "已在本机解析出金额、收支、分类和账户。点“确认入账”才会写账；写入后可以撤销。",
            tag: "待确认"
        )
    }

    private func missingLabels(for parsed: QuickEntryParser.ParsedEntry) -> [String] {
        var missing: [String] = []
        if parsed.amount == nil { missing.append("金额") }
        if parsed.type == nil { missing.append("收支") }
        if parsed.category == nil { missing.append("分类") }
        if parsed.account == nil { missing.append("账户") }
        if parsed.issues.contains(.multipleAmounts) { missing.append("确认用哪一笔金额") }
        if parsed.issues.contains(.inputTooLong) { missing.append("缩短输入") }
        return missing
    }

    private func presentConfirmedAction(question: String, routed: AIRoutedAction) {
        let advice: FinanceAdvice
        switch routed.intent {
        case .exportCSV:
            advice = FinanceAdvice(
                title: "这个动作需要你确认",
                body: "会把本机账本导出成 CSV。点下面的按钮后由系统文件面板选择保存位置；数据不会离开这台设备。",
                tag: "待确认"
            )
        case .backupJSON:
            advice = FinanceAdvice(
                title: "这个动作需要你确认",
                body: "会读取本机全部账本并生成 JSON 备份。点下面的按钮后由系统文件面板选择保存位置；数据不会离开这台设备。",
                tag: "待确认"
            )
        case .imageImport:
            advice = FinanceAdvice(
                title: "这个动作需要你确认",
                body: "图片记账要先选图或拍照，识别结果还要逐笔确认才会入账。也可以从首页的「+」进入图片记账。",
                tag: "待确认"
            )
        default:
            advice = FinanceAdvice(
                title: "这个动作需要你确认",
                body: "这个动作还没有实现。",
                tag: "待确认"
            )
        }

        let exchange = FinanceExchange(question: question, advice: advice)
        exchanges.append(exchange)
        actionCards[exchange.id] = FinanceActionCardState(
            confirmation: AIActionConfirmation(action: routed),
            parsed: nil,
            failure: nil,
            notice: nil
        )
    }

    // MARK: - Action cards

    @ViewBuilder
    private func actionSection(exchangeID: UUID, card: FinanceActionCardState) -> some View {
        switch card.confirmation.intent {
        case .record:
            recordActionCard(exchangeID: exchangeID, card: card)
        case .exportCSV, .backupJSON, .imageImport:
            confirmedActionCard(exchangeID: exchangeID, card: card)
        case .query, .unknown:
            EmptyView()
        }
    }

    private func recordActionCard(exchangeID: UUID, card: FinanceActionCardState) -> some View {
        let isReady = card.parsed?.isReadyToSave == true

        return VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(
                    systemName: card.confirmation.isUndoable
                        ? "checkmark.seal.fill"
                        : "checkmark.circle"
                )
                .font(theme.badgeFont)
                .foregroundStyle(
                    card.confirmation.isUndoable ? theme.income : theme.accentText
                )

                Text(
                    card.confirmation.isUndoable
                        ? "已入账，可撤销"
                        : (isReady ? "准备记一笔" : "还差信息")
                )
                    .font(theme.badgeFont.weight(.semibold))
                    .foregroundStyle(
                        card.confirmation.isUndoable ? theme.income : theme.accentText
                    )

                Spacer(minLength: 4)

                Text(
                    card.confirmation.isUndoable
                        ? "已写入"
                        : (isReady ? "待确认" : "未入账")
                )
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
            }

            if let parsed = card.parsed {
                if parsed.isReadyToSave {
                    recordRow("金额", MoneyFormat.currency(parsed.amount ?? 0))
                    recordRow("类型", parsed.type?.displayName ?? "—")
                    recordRow("分类", parsed.category?.name ?? "—")
                    recordRow("账户", parsed.account?.name ?? "—")
                    recordRow("备注", parsed.remark.isEmpty ? "—" : parsed.remark)
                } else {
                    let missing = missingLabels(for: parsed)
                    Text(
                        missing.isEmpty
                            ? "解析结果不完整，先不写账。"
                            : "还缺：\(missing.joined(separator: "、"))。"
                    )
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    if let issue = parsed.issues.first {
                        Text(issue.message)
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let failure = card.failure {
                Text(failure)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.expense)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = card.notice {
                Text(notice)
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if card.confirmation.isUndoable {
                actionButton(title: "撤销这笔", systemImage: "arrow.uturn.backward") {
                    undoRecord(exchangeID: exchangeID)
                }
            } else if isReady {
                actionButton(title: "确认入账", systemImage: "checkmark") {
                    confirmRecord(exchangeID: exchangeID)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.accent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func confirmedActionCard(
        exchangeID: UUID,
        card: FinanceActionCardState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "hand.raised")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.accentText)

                Text(card.importSessionIDs.isEmpty ? "这个动作需要你确认" : "已完成，可撤销")
                    .font(theme.badgeFont.weight(.semibold))
                    .foregroundStyle(theme.accentText)

                Spacer(minLength: 4)

                Text(card.confirmation.intent.displayName)
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
            }

            Text(actionDetail(for: card.confirmation.intent))
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let failure = card.failure {
                Text(failure)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.expense)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = card.notice {
                Text(notice)
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !card.importSessionIDs.isEmpty {
                actionButton(title: "撤销这次导入", systemImage: "arrow.uturn.backward") {
                    undoImageImport(exchangeID: exchangeID)
                }
            } else {
                switch card.confirmation.intent {
                case .exportCSV:
                    actionButton(title: "导出 CSV", systemImage: "square.and.arrow.up") {
                        prepareExport(exchangeID: exchangeID)
                    }
                case .backupJSON:
                    actionButton(title: "导出 JSON 备份", systemImage: "archivebox") {
                        prepareBackup(exchangeID: exchangeID)
                    }
                case .imageImport:
                    actionButton(title: "打开图片记账", systemImage: "photo") {
                        imageFlowExchangeID = exchangeID
                        activeSheet = .image
                    }
                default:
                    EmptyView()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.accent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func actionDetail(for intent: AIActionIntent) -> String {
        switch intent {
        case .exportCSV:
            return "会读取本机账本并生成 CSV，然后由系统文件面板选择保存位置。"
        case .backupJSON:
            return "会读取本机全部账本并生成 JSON 备份，然后由系统文件面板选择保存位置。"
        case .imageImport:
            return "选图或拍照后本地 OCR 识别，核对并确认才会入账。也可以从首页的「+」进入图片记账。"
        default:
            return "这个动作还没有实现。"
        }
    }

    private func recordRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)
                .frame(width: 34, alignment: .leading)

            Text(value)
                .font(theme.captionFont)
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(theme.badgeFont)
                Text(title)
                    .font(theme.buttonLabelFont)
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Action execution

    private func confirmRecord(exchangeID: UUID) {
        guard var card = actionCards[exchangeID] else { return }

        guard let parsed = card.parsed,
              let amount = parsed.amount,
              amount > 0,
              let type = parsed.type,
              let accountOption = parsed.account,
              let account = accounts.first(where: { $0.id == accountOption.id }) else {
            card.failure = "这笔记录还不完整，请重新输入这句话。"
            actionCards[exchangeID] = card
            return
        }

        let expectedKind: CategoryKind = type == .income ? .income : .expense
        guard let categoryOption = parsed.category,
              let category = categories.first(where: {
                  $0.id == categoryOption.id
                      && $0.isSelectable
                      && $0.categoryKind == expectedKind
              }) else {
            card.failure = "分类对不上，请重新输入这句话。"
            actionCards[exchangeID] = card
            return
        }

        do {
            let transaction = try LedgerService.record(
                type: type,
                amount: amount,
                date: Date(),
                note: parsed.remark,
                account: account,
                category: category,
                in: viewContext
            )
            card.confirmation.markCompleted(transactionID: transaction.id)
            card.failure = nil
            card.notice = "已入账。金额、分类和账户都来自你确认过的解析结果。"
            actionCards[exchangeID] = card
        } catch {
            card.failure = error.localizedDescription
            actionCards[exchangeID] = card
        }
    }

    private func undoRecord(exchangeID: UUID) {
        guard var card = actionCards[exchangeID],
              let transactionID = card.confirmation.completedTransactionID else {
            return
        }

        guard let transaction = transactions.first(where: { $0.id == transactionID }) else {
            card.confirmation.revokeCompletion()
            card.failure = "找不到这笔交易，可能已在别处删除。"
            actionCards[exchangeID] = card
            return
        }

        do {
            try LedgerService.delete(transaction, in: viewContext)
            card.confirmation.revokeCompletion()
            card.failure = nil
            card.notice = "已撤销：这笔交易已删除，账户余额已恢复。"
        } catch {
            card.failure = error.localizedDescription
        }
        actionCards[exchangeID] = card
    }

    private func prepareBackup(exchangeID: UUID) {
        guard var card = actionCards[exchangeID] else { return }

        do {
            backupData = try LedgerBackupService.makeBackup(context: viewContext)
            backupFilename = "LedgerBox-backup-\(exportTimestamp)"
            card.confirmation.confirm()
            card.failure = nil
            card.notice = "已生成 JSON 备份，等待你选择保存位置。"
            actionCards[exchangeID] = card
            backupExchangeID = exchangeID
            showingBackupExporter = true
        } catch {
            card.failure = "备份失败：\(error.localizedDescription)"
            actionCards[exchangeID] = card
        }
    }

    private func finishBackupExport(error: Error?) {
        guard let exchangeID = backupExchangeID,
              var card = actionCards[exchangeID] else {
            backupExchangeID = nil
            return
        }

        if let error, !isUserCancellation(error) {
            card.failure = "备份失败：\(error.localizedDescription)"
        } else if error != nil {
            card.failure = nil
            card.notice = "已取消备份，没有写入任何文件。"
        } else {
            card.failure = nil
            card.notice = "JSON 备份已导出到你选择的位置。"
        }
        actionCards[exchangeID] = card
        backupExchangeID = nil
    }

    private func prepareExport(exchangeID: UUID) {
        guard var card = actionCards[exchangeID] else { return }

        csvText = CSVExporter.makeCSV(
            transactions: Array(transactions),
            accounts: Array(accounts),
            categories: Array(categories)
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        exportFilename = "LedgerBox-\(formatter.string(from: Date()))"

        card.confirmation.confirm()
        card.failure = nil
        card.notice = "已生成 CSV，等待你选择保存位置。"
        actionCards[exchangeID] = card

        exportExchangeID = exchangeID
        showingExporter = true
    }

    private func finishExport(error: Error?) {
        guard let exchangeID = exportExchangeID,
              var card = actionCards[exchangeID] else {
            exportExchangeID = nil
            return
        }

        if let error {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == CocoaError.userCancelled.rawValue {
                card.failure = nil
                card.notice = "已取消导出，没有写入任何文件。"
            } else {
                card.failure = "导出失败：\(error.localizedDescription)"
            }
        } else {
            card.failure = nil
            card.notice = "CSV 已导出到你选择的位置。"
        }
        actionCards[exchangeID] = card
        exportExchangeID = nil
    }

    private func imageImportDidCommit(_ sessions: [ImportSession]) {
        guard let exchangeID = imageFlowExchangeID,
              var card = actionCards[exchangeID] else {
            imageFlowExchangeID = nil
            return
        }

        card.confirmation.confirm()
        card.failure = nil
        card.notice = "图片记账已完成，导入了 \(sessions.reduce(0) { $0 + $1.transactionIDs.count }) 笔。"
        card.importSessionIDs = sessions.map(\.id)
        actionCards[exchangeID] = card
        imageFlowExchangeID = nil
    }

    private func undoImageImport(exchangeID: UUID) {
        guard var card = actionCards[exchangeID], !card.importSessionIDs.isEmpty else {
            return
        }

        var firstError: Error?
        for sessionID in card.importSessionIDs {
            do {
                try ImportCommitService.undo(sessionID: sessionID, context: viewContext)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            card.failure = firstError.localizedDescription
        } else {
            card.failure = nil
            card.notice = "已撤销图片导入：相关交易已删除，余额已恢复。"
            card.importSessionIDs = []
            card.confirmation.revokeCompletion()
        }
        actionCards[exchangeID] = card
    }

    private var exportTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.userCancelled.rawValue
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
