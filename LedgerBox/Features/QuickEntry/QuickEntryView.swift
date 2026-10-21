import AVFoundation
import Combine
import CoreData
import Dispatch
import Foundation
import Speech
import SwiftUI

// MARK: - On-device speech

/// A deliberately small Speech wrapper. It never falls back to Apple's server
/// recognizer: if on-device recognition is unavailable, the UI asks the user to
/// type instead. [隐私边界] [无网络 API]
final class QuickEntrySpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var isStopped = true

    var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func start() {
        guard !isRecording, isStopped else {
            return
        }

        errorMessage = nil
        transcript = ""
        isStopped = false

        guard let recognizer else {
            isStopped = true
            errorMessage = "当前设备不支持中文语音识别，请使用键盘输入。"
            return
        }

        guard recognizer.supportsOnDeviceRecognition else {
            isStopped = true
            errorMessage = "当前设备不支持本地中文语音识别。为避免上传音频，请使用键盘输入。"
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, !self.isStopped else {
                    return
                }

                switch status {
                case .authorized:
                    self.requestMicrophonePermission()
                case .denied, .restricted:
                    self.isStopped = true
                    self.errorMessage = "语音识别权限未开启，请在系统设置中允许 LedgerBox 使用语音识别。"
                case .notDetermined:
                    self.isStopped = true
                    self.errorMessage = "尚未获得语音识别权限。"
                @unknown default:
                    self.isStopped = true
                    self.errorMessage = "语音识别权限状态未知。"
                }
            }
        }
    }

    func stop() {
        isStopped = true
        guard isRecording else {
            return
        }

        isRecording = false
        request?.endAudio()
        audioEngine.stop()

        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        request = nil
        task = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, !self.isStopped else {
                    return
                }

                if granted {
                    self.beginRecognition()
                } else {
                    self.isStopped = true
                    self.errorMessage = "麦克风权限未开启，请在系统设置中允许 LedgerBox 使用麦克风。"
                }
            }
        }
    }

    private func beginRecognition() {
        guard !isStopped else {
            return
        }
        guard let recognizer else {
            isStopped = true
            errorMessage = "当前设备不支持中文语音识别，请使用键盘输入。"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            isStopped = true
            errorMessage = "无法启动录音：\(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            isStopped = true
            errorMessage = "没有可用的麦克风输入。"
            cleanupAudio()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            isStopped = true
            cleanupAudio()
            errorMessage = "无法启动录音：\(error.localizedDescription)"
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stop()
                    }
                }

                if let error, self.isRecording {
                    self.errorMessage = "语音识别失败：\(error.localizedDescription)"
                    self.stop()
                }
            }
        }
    }

    private func cleanupAudio() {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

// MARK: - Quick entry panel

struct QuickEntryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var categories: FetchedResults<Category>

    @StateObject private var speech = QuickEntrySpeechRecognizer()
    @State private var text = ""
    @State private var parsed: QuickEntryParser.ParsedEntry?
    @State private var selectedType: TransactionType?
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
    @State private var autoType: TransactionType?
    @State private var autoCategoryID: UUID?
    @State private var autoAccountID: UUID?

    // These flags distinguish "not touched yet" from "the user explicitly
    // cleared this field". A nil selection alone cannot tell them apart.
    @State private var typeManuallyEdited = false
    @State private var categoryManuallyEdited = false
    @State private var accountManuallyEdited = false
    @State private var date = Date()
    @State private var amountText = ""
    @State private var lastAutoAmount = ""
    @State private var note = ""
    @State private var lastAutoRemark = ""
    @State private var alert: QuickEntryAlert?
    @FocusState private var inputFocused: Bool

    private let parser = QuickEntryParser()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    inputCard
                    previewCard
                    detailsCard
                    saveButton
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("极速记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        speech.stop()
                        dismiss()
                    }
                    .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .tint(theme.accent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(speech.isRecording)
        .onAppear {
            reparse()
        }
        .onDisappear {
            speech.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, speech.isRecording {
                speech.stop()
            }
        }
        .onChange(of: text) { _, _ in
            reparse()
        }
        .onChange(of: amountText) { _, newValue in
            sanitizeAmount(newValue)
        }
        .onChange(of: speech.transcript) { _, newValue in
            guard !newValue.isEmpty else {
                return
            }
            if text != newValue {
                text = newValue
            }
        }
        .onChange(of: speech.errorMessage) { _, newValue in
            if let newValue {
                alert = QuickEntryAlert(message: newValue)
                speech.clearError()
            }
        }
        .onChange(of: categorySignature) { _, _ in
            normalizeSelection()
            reparse()
        }
        .onChange(of: accounts.count) { _, _ in
            reparse()
        }
        .alert(item: $alert) { item in
            Alert(
                title: Text("极速记账"),
                message: Text(item.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    // MARK: - Cards

    private var inputCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                Text("一句话记账")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                HStack(alignment: .bottom, spacing: theme.smallSpacing) {
                    TextField("例如：微信买奶茶 15 元", text: $text, axis: .vertical)
                        .focused($inputFocused)
                        .font(theme.bodyFont)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(
                            theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )

                    Button {
                        toggleSpeech()
                    } label: {
                        Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                            .font(theme.headerActionFont)
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 48, height: 48)
                            .background(
                                speech.isRecording ? theme.expense : theme.accent,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speech.isRecording ? "停止语音输入" : "开始语音输入")
                }

                Text("语音只在本机识别；不支持本地识别时不会回退到服务器。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var previewCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("实时解析")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text(canSave ? "可保存" : "待补全")
                        .font(theme.badgeFont)
                        .foregroundStyle(canSave ? theme.income : theme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (canSave ? theme.income : theme.warning).opacity(0.12),
                            in: Capsule()
                        )
                }

                if parsed == nil {
                    Text("输入或说一句话，例如“微信买奶茶 15 元”。")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(effectiveType?.displayName ?? "待选择")
                            .font(theme.captionFont)
                            .foregroundStyle(typeColor)

                        Text(amountValue.map { MoneyFormat.currency($0) } ?? "未识别金额")
                            .font(theme.moneyFont)
                            .foregroundStyle(theme.primaryText)
                    }

                    HStack(spacing: 8) {
                        summaryChip(title: "分类", value: effectiveCategory?.name ?? "待选择")
                        summaryChip(title: "账户", value: effectiveAccount?.name ?? "待选择")
                    }

                    if !visibleIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(visibleIssues.prefix(3)), id: \.rawValue) { issue in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(issue.message)
                                        .font(theme.captionFont)
                                }
                                .foregroundStyle(theme.warning)
                            }
                        }
                    } else if !canSave {
                        Text("补全金额、分类和账户后即可保存。")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
    }

    private var detailsCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("补全信息")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                typeSelector
                amountRow
                categoryPicker
                accountPicker
                datePicker
                noteField
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: theme.smallSpacing) {
                Image(systemName: "checkmark.circle.fill")
                Text("保存并回首页")
            }
            .font(theme.buttonLabelFont)
            .foregroundStyle(canSave ? theme.onAccent : theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canSave ? theme.accent : theme.surfaceElevated,
                in: RoundedRectangle(
                    cornerRadius: theme.controlRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .accessibilityHint("保存后首页流水和余额会自动刷新")
    }

    // MARK: - Form pieces

    private var categorySelection: Binding<UUID?> {
        Binding(
            get: { selectedCategoryID },
            set: { newValue in
                selectedCategoryID = newValue
                autoCategoryID = nil
                categoryManuallyEdited = true
            }
        )
    }

    private var accountSelection: Binding<UUID?> {
        Binding(
            get: { selectedAccountID },
            set: { newValue in
                selectedAccountID = newValue
                autoAccountID = nil
                accountManuallyEdited = true
            }
        )
    }

    private func selectType(_ type: TransactionType) {
        // Tapping the already-selected type pins it against later parser
        // changes; it must still be treated as a manual choice.
        typeManuallyEdited = true
        autoType = nil

        guard selectedType != type else {
            normalizeSelection()
            reparseIfTextPresent()
            return
        }

        selectedType = type

        // Categories are kind-specific. A manual type switch invalidates the
        // old category and lets the parser suggest one for the new kind.
        selectedCategoryID = nil
        autoCategoryID = nil
        categoryManuallyEdited = false

        normalizeSelection()
        reparseIfTextPresent()
    }

    private func reparseIfTextPresent() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        reparse()
    }

    private var typeSelector: some View {
        HStack(spacing: 8) {
            ForEach([TransactionType.expense, TransactionType.income]) { type in
                Button {
                    selectType(type)
                } label: {
                    Text(type.displayName)
                        .font(theme.buttonLabelFont)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(
                            effectiveType == type ? theme.onAccent : theme.secondaryText
                        )
                        .background(
                            effectiveType == type ? theme.accent : theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var amountRow: some View {
        HStack(spacing: 12) {
            Text("金额")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

            Spacer(minLength: 8)

            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(theme.rowMoneyFont)
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: 160)
        }
        .padding(.vertical, 2)
    }

    private var categoryPicker: some View {
        Picker("分类", selection: categorySelection) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(filteredCategories, id: \.id) { category in
                Text(category.name).tag(Optional(category.id))
            }
        }
        .pickerStyle(.menu)
        .tint(theme.accent)
    }

    private var accountPicker: some View {
        Picker("账户", selection: accountSelection) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(accounts, id: \.id) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
        .pickerStyle(.menu)
        .tint(theme.accent)
    }

    private var datePicker: some View {
        DatePicker(
            "日期",
            selection: $date,
            in: ...Date(),
            displayedComponents: .date
        )
        .font(theme.captionFont)
        .foregroundStyle(theme.secondaryText)
    }

    private var noteField: some View {
        TextField("备注", text: $note)
            .font(theme.bodyFont)
            .foregroundStyle(theme.primaryText)
            .padding(12)
            .background(
                theme.surfaceElevated,
                in: RoundedRectangle(
                    cornerRadius: theme.controlRadius,
                    style: .continuous
                )
            )
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(theme.captionFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            theme.surfaceElevated,
            in: RoundedRectangle(
                cornerRadius: theme.controlRadius,
                style: .continuous
            )
        )
    }

    // MARK: - State

    private var categoryOptions: [QuickEntryParser.CategoryOption] {
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

    private var accountOptions: [QuickEntryParser.AccountOption] {
        accounts.map {
            QuickEntryParser.AccountOption(id: $0.id, name: $0.name)
        }
    }

    private var effectiveType: TransactionType? {
        selectedType ?? parsed?.type
    }

    private var categoryKindForSelection: CategoryKind {
        effectiveType == .income ? .income : .expense
    }

    // Count alone misses soft-deletes, which keep the row count unchanged.
    private var categorySignature: [String] {
        categories.map {
            [
                $0.id.uuidString,
                String($0.isSoftDeleted),
                $0.kind,
                $0.name
            ].joined(separator: "|")
        }
    }

    private var filteredCategories: [Category] {
        categories.filter {
            $0.isSelectable && $0.categoryKind == categoryKindForSelection
        }
    }

    private var effectiveCategory: Category? {
        guard
            let selectedCategoryID,
            let effectiveType
        else {
            return nil
        }

        let kind: CategoryKind = effectiveType == .income ? .income : .expense
        return categories.first {
            $0.id == selectedCategoryID
                && $0.isSelectable
                && $0.categoryKind == kind
        }
    }

    private var effectiveAccount: Account? {
        guard let selectedAccountID else {
            return nil
        }
        return accounts.first { $0.id == selectedAccountID }
    }

    private var amountValue: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else {
            return nil
        }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var typeColor: Color {
        if effectiveType == .income {
            return theme.income
        }
        if effectiveType == .expense {
            return theme.expense
        }
        return theme.secondaryText
    }

    private var hasBlockingIssue: Bool {
        guard let parsed else {
            return false
        }
        return parsed.issues.contains {
            $0 == .multipleAmounts || $0 == .inputTooLong
        }
    }

    private var visibleIssues: [QuickEntryParser.Issue] {
        guard let parsed else {
            return []
        }

        return parsed.issues.filter { issue in
            switch issue {
            case .missingAmount:
                return amountValue == nil
            case .invalidAmount, .negativeAmount:
                return amountValue == nil || (amountValue ?? 0) <= 0
            case .missingType, .ambiguousType:
                return effectiveType == nil
            case .missingCategory, .ambiguousCategory:
                return effectiveCategory == nil
            case .missingAccount, .ambiguousAccount:
                return effectiveAccount == nil
            case .multipleAmounts, .inputTooLong:
                return true
            case .emptyInput:
                return false
            }
        }
    }

    private var canSave: Bool {
        guard
            let amountValue,
            amountValue > 0,
            effectiveType != nil,
            effectiveCategory != nil,
            effectiveAccount != nil,
            date <= Date(),
            !hasBlockingIssue
        else {
            return false
        }
        return true
    }

    // MARK: - Actions

    private func toggleSpeech() {
        if speech.isRecording {
            speech.stop()
        } else {
            inputFocused = false
            speech.start()
        }
    }

    private func reparse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsed = nil
            selectedType = nil
            selectedCategoryID = nil
            selectedAccountID = nil
            autoType = nil
            autoCategoryID = nil
            autoAccountID = nil
            typeManuallyEdited = false
            categoryManuallyEdited = false
            accountManuallyEdited = false
            if amountText == lastAutoAmount {
                amountText = ""
                lastAutoAmount = ""
            }
            if note == lastAutoRemark {
                note = ""
                lastAutoRemark = ""
            }
            return
        }

        let result = parser.parse(
            trimmed,
            categories: categoryOptions,
            accounts: accountOptions
        )
        parsed = result

        // Only follow the parser while the field is untouched or still holds the
        // parser's previous suggestion. Once the user overrides a field, keep it.
        if let type = result.type {
            if !typeManuallyEdited,
               (selectedType == nil || selectedType == autoType) {
                autoType = type
                selectedType = type
            }
        } else if !typeManuallyEdited, selectedType == autoType {
            selectedType = nil
            autoType = nil
        }

        if let category = result.category {
            if !categoryManuallyEdited,
               selectedCategoryID == nil || selectedCategoryID == autoCategoryID {
                autoCategoryID = category.id
                selectedCategoryID = category.id
            }
        } else if !categoryManuallyEdited, selectedCategoryID == autoCategoryID {
            selectedCategoryID = nil
            autoCategoryID = nil
        }

        if let account = result.account {
            if !accountManuallyEdited,
               selectedAccountID == nil || selectedAccountID == autoAccountID {
                autoAccountID = account.id
                selectedAccountID = account.id
            }
        } else if !accountManuallyEdited, selectedAccountID == autoAccountID {
            selectedAccountID = nil
            autoAccountID = nil
        }

        if let amount = result.amount {
            let formatted = MoneyFormat.editable(amount)
            if amountText.isEmpty || amountText == lastAutoAmount {
                amountText = formatted
                lastAutoAmount = formatted
            }
        } else if amountText == lastAutoAmount {
            amountText = ""
            lastAutoAmount = ""
        }

        if note.isEmpty || note == lastAutoRemark {
            note = result.remark
            lastAutoRemark = result.remark
        }

        normalizeSelection()
    }

    private func normalizeSelection() {
        let validCategoryIDs = Set(filteredCategories.map(\.id))
        if let selectedCategoryID, !validCategoryIDs.contains(selectedCategoryID) {
            self.selectedCategoryID = nil
            autoCategoryID = nil
            // The row disappeared or the type changed; this was not an
            // intentional clear, so allow the parser to suggest again.
            categoryManuallyEdited = false
        }

        if let selectedAccountID,
           !accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = nil
            autoAccountID = nil
            accountManuallyEdited = false
        }
    }

    private func sanitizeAmount(_ rawValue: String) {
        var filtered = rawValue.replacingOccurrences(of: ",", with: ".")
        filtered = String(filtered.filter { "0123456789.".contains($0) })

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
            amountText = filtered
        }
    }

    private func save() {
        guard
            let amountValue,
            amountValue > 0,
            let type = effectiveType,
            let category = effectiveCategory,
            let account = effectiveAccount
        else {
            alert = QuickEntryAlert(message: "请补全金额、收支、分类和账户。")
            return
        }

        guard date <= Date() else {
            alert = QuickEntryAlert(message: "记账日期不能晚于当前时间。")
            return
        }

        guard !hasBlockingIssue else {
            alert = QuickEntryAlert(message: "当前输入存在多笔金额或超长内容，请缩短后再保存。")
            return
        }

        do {
            try LedgerService.record(
                type: type,
                amount: amountValue,
                date: date,
                note: note,
                account: account,
                category: category,
                in: viewContext
            )
            speech.stop()
            dismiss()
        } catch {
            alert = QuickEntryAlert(message: error.localizedDescription)
        }
    }
}

private struct QuickEntryAlert: Identifiable {
    let id = UUID()
    let message: String
}

#Preview("极速记账 · 浅色") {
    QuickEntryView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("极速记账 · 深色") {
    QuickEntryView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
