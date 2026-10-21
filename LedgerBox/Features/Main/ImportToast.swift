import Foundation
import SwiftUI

struct ImportToast: Identifiable, Equatable {
    let id = UUID()
    let sessionID: UUID
    let message: String
}

/// A short-lived undo affordance. The session is already persisted by
/// `ImportHistoryStore`; this object only owns presentation and the timer.
@MainActor
final class ImportToastCenter: ObservableObject {
    @Published private(set) var toast: ImportToast?

    private var dismissTask: Task<Void, Never>?

    func show(sessionID: UUID, count: Int) {
        dismissTask?.cancel()
        toast = ImportToast(
            sessionID: sessionID,
            message: count == 1 ? "已入账 1 笔，可撤销" : "已入账 \(count) 笔，可撤销"
        )

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toast = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        toast = nil
    }

    deinit {
        dismissTask?.cancel()
    }
}

struct ImportToastView: View {
    let toast: ImportToast
    let onUndo: () -> Void

    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(theme.controlIconFont)
                .foregroundStyle(theme.income)

            Text(toast.message)
                .font(theme.captionFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("撤销", action: onUndo)
                .font(theme.captionFont.weight(.semibold))
                .foregroundStyle(theme.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint("删除刚刚导入的账单并恢复账户余额")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            theme.surfaceElevated,
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(theme.separator, lineWidth: theme.hairline)
        }
    }
}
