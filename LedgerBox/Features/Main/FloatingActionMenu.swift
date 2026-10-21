import SwiftUI
import UIKit

/// Two-action entry point. The 62pt main button is designed to sit in the
/// center of the custom bottom bar; expanded actions grow upward and to the
/// left so they stay on screen. It does not reserve bar space by itself.
struct FloatingActionMenu: View {
    @Binding var isExpanded: Bool

    private let onQuickEntry: () -> Void
    private let onManualEntry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isExpanded: Binding<Bool>,
        onQuickEntry: @escaping () -> Void,
        onManualEntry: @escaping () -> Void
    ) {
        self._isExpanded = isExpanded
        self.onQuickEntry = onQuickEntry
        self.onManualEntry = onManualEntry
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainButton
                .zIndex(1)

            if isExpanded {
                VStack(alignment: .trailing, spacing: 10) {
                    actionButton(
                        title: "极速记账",
                        subtitle: "相机 / 相册识别",
                        systemImage: "bolt.fill",
                        accessibilityLabel: "极速记账，相机或相册识别",
                        accessibilityHint: "打开相机或相册识别记账",
                        action: onQuickEntry
                    )

                    actionButton(
                        title: "记一笔",
                        subtitle: "手动填写金额与分类",
                        systemImage: "square.and.pencil",
                        accessibilityLabel: "记一笔，手动记账",
                        accessibilityHint: "打开手动记账表单",
                        action: onManualEntry
                    )
                }
                .fixedSize()
                .offset(y: -72)
                .transition(actionTransition)
            }
        }
        .frame(width: 62, height: 62)
        .animation(menuAnimation, value: isExpanded)
    }

    // MARK: - Main FAB

    private var mainButton: some View {
        Button {
            softImpact()
            isExpanded.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        Color(
                            .sRGB,
                            red: 20.0 / 255.0,
                            green: 20.0 / 255.0,
                            blue: 22.0 / 255.0,
                            opacity: 0.78
                        )
                    )
                    .background(.ultraThinMaterial, in: Circle())

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.34, dampingFraction: 0.78),
                        value: isExpanded
                    )
            }
            .frame(width: 62, height: 62)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 5)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isExpanded ? "收起记账菜单" : "打开记账菜单"))
        .accessibilityValue(Text(isExpanded ? "已展开两个记账选项" : "已收起"))
        .accessibilityHint(
            Text(
                isExpanded
                    ? "轻点收起；上方有极速记账和记一笔两个选项"
                    : "轻点展开极速记账与记一笔"
            )
        )
    }

    // MARK: - Expanded actions

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            softImpact()
            isExpanded = false
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(.callout, design: .rounded, weight: .semibold))

                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        Color(
                            .sRGB,
                            red: 20.0 / 255.0,
                            green: 20.0 / 255.0,
                            blue: 22.0 / 255.0,
                            opacity: 0.72
                        )
                    )
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(accessibilityHint))
    }

    // MARK: - Motion & feedback

    private var menuAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.34, dampingFraction: 0.78)
    }

    private var actionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private func softImpact() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }
}
