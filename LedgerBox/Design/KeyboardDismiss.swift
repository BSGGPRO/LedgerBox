import SwiftUI

// MARK: - Shared keyboard dismissal
//
// Why this file exists: amount fields use `.decimalPad`, which has no Return
// key, and multiline fields turn Return into a line break. Either way the
// keyboard used to stay up until the user scrolled the form or left the page.
//
// Every input in the app now gets the same exits:
//   1. a "完成" button in a `ToolbarItemGroup(placement: .keyboard)` accessory
//      bar (`.keyboardDoneBar`), driven by the view's own `@FocusState`, and
//   2. a transparent tap target behind the form content
//      (`.keyboardDismissOnBlankTap`), so tapping blank space ends editing too.
//
// Only public SwiftUI API is used: `@FocusState` plus keyboard toolbar items.
// No `resignFirstResponder` poking, no private API and no third-party
// dependency, so the focused view stays in charge of its own editing state.

enum LedgerKeyboard {
    /// Title of the accessory bar button; one string keeps every screen alike.
    static let doneTitle = "完成"
}

// MARK: - Keyboard "完成" accessory bar

/// Adds the keyboard accessory bar with a trailing "完成" button.
private struct KeyboardDoneBarModifier: ViewModifier {
    @Environment(\.ledgerTheme) private var theme

    let title: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button(title, action: action)
                    .font(theme.buttonLabelFont)
                    .foregroundStyle(theme.accentText)
                    .accessibilityLabel("完成，收起键盘")
            }
        }
    }
}

// MARK: - Blank-space tap target

/// Transparent tap target used by `.keyboardDismissOnBlankTap(_:)`.
///
/// It must sit *behind* the form content: a tap gesture on top of (or as an
/// ancestor of) the fields competes with the fields themselves and can make a
/// `TextField` lose focus the moment the user taps it.
struct KeyboardDismissArea: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityHidden(true)
    }
}

// MARK: - View helpers

extension View {
    /// Adds a "完成" button above the keyboard that runs `action`.
    ///
    /// Apply it to the scrolling content *inside* the `NavigationStack`:
    /// ```swift
    /// ScrollView { … }
    ///     .keyboardDoneBar { focusedField = nil }
    /// ```
    func keyboardDoneBar(
        _ title: String = LedgerKeyboard.doneTitle,
        action: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardDoneBarModifier(title: title, action: action))
    }

    /// `.keyboardDoneBar` that only exists while `isEnabled` is true.
    ///
    /// Used by screens that swap between two input surfaces: only one of them
    /// may contribute the bar, otherwise two "完成" buttons would be merged
    /// into the same accessory bar.
    @ViewBuilder
    func keyboardDoneBar(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isEnabled {
            keyboardDoneBar(action: action)
        } else {
            self
        }
    }

    /// Puts a tap target behind this view so blank-space taps end editing
    /// without stealing taps from buttons, pickers or text fields.
    ///
    /// The closure is required on purpose: the owner of the `@FocusState`
    /// clears its own focus, so no view has to resign a responder it does not
    /// own.
    func keyboardDismissOnBlankTap(_ action: @escaping () -> Void) -> some View {
        background {
            KeyboardDismissArea(action: action)
        }
    }
}
