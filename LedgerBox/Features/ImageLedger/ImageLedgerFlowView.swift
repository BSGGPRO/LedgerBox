import CoreData
import PhotosUI
import SwiftUI
import UIKit

/// Screenshot-to-draft flow. The only write happens after the user reviews this
/// screen; OCR never writes a transaction directly.
@MainActor
struct ImageLedgerFlowView: View {
    let onCommitted: (ImportSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.ledgerTheme) private var theme

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)
        ]
    )
    private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)
        ]
    )
    private var categories: FetchedResults<Category>

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var draft: ImportDraft?
    @State private var duplicateSession: ImportSession?
    @State private var errorMessage: String?

    // Editable copy. `ImportDraft` remains immutable so the original OCR result
    // is preserved until the user explicitly confirms their corrections.
    @State private var merchant = ""
    @State private var amountText = ""
    @State private var feeText = ""
    @State private var date = Date()
    @State private var type: TransactionType = .expense
    @State private var category: LedgerCategory = .other
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var note = ""
    @State private var feeMode: FeeMode = .feeDeductedFromPrincipal

    @FocusState private var amountFocused: Bool

    var body: some View {
        GlassHeaderHost(
            title: "图片记账",
            subtitle: "本地 OCR · 不联网",
            trailing: { closeButton }
        ) {
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                if isProcessing {
                    processingCard
                } else if let draft {
                    reviewContent(draft)
                } else {
                    pickerContent
                }
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.top, theme.cardSpacing)
            .padding(.bottom, 40)
        }
        .tint(theme.accentText)
        .keyboardDoneBar { amountFocused = false }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if accountID == nil {
                accountID = accounts.first(where: { !$0.locked })?.id
                    ?? accounts.first?.id
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            loadPhoto(item)
        }
        .sheet(isPresented: $showingCamera) {
            ReceiptCameraPicker { image in
                selectedImage = image
                recognize(image)
            }
        }
        .alert(
            "无法完成导入",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Pick

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            LedgerCard {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    HStack(spacing: theme.cardSpacing) {
                        LedgerIconBadge(
                            systemName: "text.viewfinder",
                            tint: theme.accentText,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("拍账单，先核对再入账")
                                .font(theme.sectionTitleFont)
                                .foregroundStyle(theme.primaryText)

                            Text("金额、时间、订单号由本地规则提取；模型只辅助分类。")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("图片只在设备上识别，不上传服务器。订单号仅保存 SHA-256 哈希。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: theme.smallSpacing) {
                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
                            } else {
                                errorMessage = "当前设备没有可用相机，请从相册选择截图。"
                            }
                        } label: {
                            Label("拍照识别", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(
                            LedgerPrimaryButtonStyle(theme: theme, fullWidth: true)
                        )

                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("从相册选择", systemImage: "photo.on.rectangle")
                                .font(theme.bodyFont.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.primaryText)
                        .background(
                            theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.cardRadius,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: theme.cardRadius,
                                style: .continuous
                            )
                            .strokeBorder(theme.borderStrong, lineWidth: theme.hairline)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: theme.smallSpacing) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(theme.income)
                Text("识别失败不会写入任何账单。确认前可以修改金额、分类、账户和时间。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, theme.smallSpacing)
        }
    }

    private var processingCard: some View {
        LedgerCard {
            VStack(spacing: theme.spacing) {
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.accentText)

                Text("正在本机识别…")
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.primaryText)

                Text("OCR、规则解析和分类都在设备上完成。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在本机识别账单")
    }

    // MARK: - Review

    private func reviewContent(_ draft: ImportDraft) -> some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            summaryCard(draft)

            if let duplicateSession {
                Label(
                    "这笔账单已在 \(duplicateSession.createdAt.formatted(date: .abbreviated, time: .shortened)) 导入过，已阻止重复入账。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(theme.captionFont)
                .foregroundStyle(theme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.smallSpacing)
            }

            if !draft.warnings.isEmpty {
                warningCard(draft.warnings)
            }

            editCard(draft)

            if let split = draft.transferSplit, split.fee > 0 {
                feeModeCard(split)
            }

            rawTextDisclosure(draft)

            Button {
                confirm(draft)
            } label: {
                Text(duplicateSession == nil ? "确认入账" : "已存在，无法重复入账")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(LedgerPrimaryButtonStyle(theme: theme, fullWidth: true))
            .disabled(duplicateSession != nil || parsedAmount == nil || selectedAccount == nil)
            .opacity(duplicateSession == nil ? 1 : 0.55)

            Button("重新选择图片") {
                reset()
            }
            .font(theme.captionFont.weight(.semibold))
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func summaryCard(_ draft: ImportDraft) -> some View {
        LedgerCard(surface: .elevated) {
            VStack(alignment: .leading, spacing: theme.cardSpacing) {
                HStack(spacing: theme.smallSpacing) {
                    LedgerTag(sourceName(draft.source), tint: theme.accentText)
                    if draft.needsReview {
                        LedgerTag("需核对", tint: theme.warning)
                    }
                    Spacer(minLength: 4)
                    Text("模型 \(Int((draft.modelConfidence * 100).rounded()))%")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.tertiaryText)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                    Text(amountText.isEmpty ? MoneyFormat.editable(draft.amount) : amountText)
                        .font(theme.amountFont)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Text(merchant.isEmpty ? draft.merchant : merchant)
                    .font(theme.bodyFont.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                Text(draft.category.displayName + " · " + type.displayName)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func warningCard(_ warnings: [ReceiptWarning]) -> some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                Label("请核对", systemImage: "checklist")
                    .font(theme.captionFont.weight(.semibold))
                    .foregroundStyle(theme.warning)

                ForEach(warnings, id: \.self) { warning in
                    Text("• " + warningText(warning))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func editCard(_ draft: ImportDraft) -> some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.cardSpacing) {
                Text("核对与修改")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                fieldRow("金额", required: true) {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .multilineTextAlignment(.trailing)
                        .font(theme.bodyFont.weight(.semibold))
                        .frame(maxWidth: 160)
                }

                fieldRow("商户") {
                    TextField("商户名称", text: $merchant)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }

                fieldRow("类型") {
                    Picker("类型", selection: $type) {
                        ForEach(TransactionType.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .tint(theme.accentText)
                }

                fieldRow("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(LedgerCategory.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .tint(theme.accentText)
                }

                fieldRow("账户") {
                    Picker("账户", selection: $accountID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(accounts, id: \.objectID) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    .labelsHidden()
                    .tint(theme.accentText)
                }

                if type == .transfer {
                    fieldRow("转入") {
                        Picker("转入账户", selection: $toAccountID) {
                            Text("请选择").tag(UUID?.none)
                            ForEach(transferTargets, id: \.objectID) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .labelsHidden()
                        .tint(theme.accentText)
                    }
                }

                fieldRow("时间") {
                    DatePicker(
                        "时间",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(theme.accentText)
                }

                fieldRow("备注") {
                    TextField("可选", text: $note)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }

                if let fee = draft.fee, fee > 0 {
                    fieldRow("手续费") {
                        TextField("0.00", text: $feeText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                }
            }
        }
    }

    private func feeModeCard(_ split: TransferSplit) -> some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                Text("手续费怎么算？")
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.primaryText)

                Picker("手续费模式", selection: $feeMode) {
                    Text("从本金扣除").tag(FeeMode.feeDeductedFromPrincipal)
                    Text("另付手续费").tag(FeeMode.feePaidSeparately)
                }
                .pickerStyle(.segmented)

                let current = split.switching(to: feeMode)
                Text(
                    "到账 \(MoneyFormat.currency(current.credited)) · 账户扣款 \(MoneyFormat.currency(current.cashOut))"
                )
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

                Text("截图无法证明手续费由哪一方承担，请按实际账单选择。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rawTextDisclosure(_ draft: ImportDraft) -> some View {
        DisclosureGroup {
            Text(draft.rawText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, theme.smallSpacing)
        } label: {
            Label("查看原始 OCR 文本", systemImage: "doc.text.magnifyingglass")
                .font(theme.captionFont.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, theme.smallSpacing)
    }

    private func fieldRow<Content: View>(
        _ title: String,
        required: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: theme.smallSpacing) {
            HStack(spacing: 2) {
                Text(title)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                if required {
                    Text("*")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.expense)
                }
            }
            Spacer(minLength: 8)
            content()
                .font(theme.bodyFont)
                .foregroundStyle(theme.primaryText)
        }
        .frame(minHeight: theme.rowMinHeight)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭图片记账")
    }

    // MARK: - Selection helpers

    private var selectedAccount: Account? {
        accounts.first(where: { $0.id == accountID })
    }

    private var transferTargets: [Account] {
        accounts.filter { $0.id != accountID }
    }

    private var parsedAmount: Decimal? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let value = Decimal(
                string: cleaned,
                locale: Locale(identifier: "en_US_POSIX")
              ),
              value > 0 else {
            return nil
        }
        return value.roundedToCents()
    }

    private var selectedCategory: Category? {
        guard type != .transfer else { return nil }
        let kind = type == .income
            ? CategoryKind.income.rawValue
            : CategoryKind.expense.rawValue
        return categories.first {
            !$0.isSoftDeleted && $0.kind == kind && $0.name == category.rawValue
        } ?? categories.first {
            !$0.isSoftDeleted && $0.name == category.rawValue
        }
    }

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isProcessing = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw ImportFlowError.unreadableImage
                }
                selectedImage = image
                recognize(image)
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func recognize(_ image: UIImage) {
        guard let cgImage = image.normalizedForOCR().cgImage else {
            isProcessing = false
            errorMessage = "无法读取这张图片，请换一张截图。"
            return
        }

        isProcessing = true
        errorMessage = nil
        draft = nil
        duplicateSession = nil

        Task.detached(priority: .userInitiated) {
            do {
                let ocr = try await VisionOCRService().recognize(cgImage: cgImage)
                guard let newDraft = ImportCommitService.makeDraft(from: ocr) else {
                    await MainActor.run {
                        isProcessing = false
                        errorMessage = "没有识别到明确金额。请换一张更清晰的账单截图，或使用手动记账。"
                    }
                    return
                }
                let existing = ImportHistoryStore.shared.duplicate(
                    for: newDraft.dedupeKey
                )
                await MainActor.run {
                    apply(newDraft, duplicate: existing)
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func apply(_ newDraft: ImportDraft, duplicate: ImportSession?) {
        draft = newDraft
        duplicateSession = duplicate
        merchant = newDraft.merchant
        amountText = MoneyFormat.editable(newDraft.amount)
        feeText = newDraft.fee.map { MoneyFormat.editable($0) } ?? ""
        date = newDraft.date
        type = newDraft.type
        category = newDraft.category
        note = newDraft.note ?? ""
        accountID = accounts.first(where: { !$0.locked })?.id ?? accounts.first?.id
        toAccountID = nil
        feeMode = newDraft.transferSplit?.mode ?? .feeDeductedFromPrincipal
    }

    private func confirm(_ original: ImportDraft) {
        guard let amount = parsedAmount else {
            errorMessage = "请输入有效金额。"
            return
        }
        guard let account = selectedAccount else {
            errorMessage = "请选择一个账户。"
            return
        }
        let target = type == .transfer
            ? accounts.first(where: { $0.id == toAccountID })
            : nil
        if type == .transfer, target == nil {
            errorMessage = "转账需要选择另一个转入账户。"
            return
        }

        let feeTextValue = feeText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fee = Decimal(
            string: feeTextValue,
            locale: Locale(identifier: "en_US_POSIX")
        )?.roundedToCents()
        if !feeTextValue.isEmpty, fee == nil {
            errorMessage = "手续费格式无效，请填写数字或留空。"
            return
        }
        let split = original.transferSplit?.switching(to: feeMode)
        let updated = ImportDraft(
            id: original.id,
            source: original.source,
            rawText: original.rawText,
            cleanText: original.cleanText,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            fee: fee,
            date: date,
            category: category,
            type: type,
            accountID: account.id,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            orderIDHash: original.orderIDHash,
            dedupeKey: ReceiptParser.dedupeKey(
                source: original.source,
                merchant: merchant,
                amount: amount,
                date: date,
                orderIDHash: original.orderIDHash
            ),
            warnings: original.warnings,
            modelConfidence: original.modelConfidence,
            needsReview: original.needsReview,
            transferSplit: split
        )

        do {
            let session = try ImportCommitService.commit(
                updated,
                account: account,
                toAccount: target,
                category: selectedCategory,
                context: viewContext
            )
            onCommitted(session)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        selectedPhoto = nil
        selectedImage = nil
        draft = nil
        duplicateSession = nil
        errorMessage = nil
        isProcessing = false
    }

    private func sourceName(_ source: ReceiptSource) -> String {
        switch source {
        case .wechat: return "微信"
        case .alipay: return "支付宝"
        case .bank: return "银行"
        case .unknown: return "图片"
        }
    }

    private func warningText(_ warning: ReceiptWarning) -> String {
        switch warning {
        case .lowOCRConfidence: return "OCR 置信度偏低，请核对金额与商户。"
        case .ambiguousAmount: return "检测到多个金额候选，已选上下文最强的一项。"
        case .missingAmount: return "未识别到金额，请手动填写。"
        case .missingDate: return "未识别到时间，已使用今天 0 点。"
        case .feeSplitAmbiguous: return "手续费可能从本金扣除，也可能另付，请确认。"
        case .modelFallback: return "本地模型未命中，分类由商户词库给出。"
        case .duplicateOrder: return "订单号与历史导入重复。"
        }
    }
}

private enum ImportFlowError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "无法读取这张图片，请换一张截图。"
        }
    }
}

private struct ReceiptCameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        private let parent: ReceiptCameraPicker

        init(parent: ReceiptCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPicked(image)
            }
            parent.dismiss()
        }
    }
}

private extension UIImage {
    /// Camera images can carry an orientation that `cgImage` drops. Redraw once
    /// so Vision sees upright pixels instead of a sideways receipt.
    func normalizedForOCR() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
