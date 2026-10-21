import SwiftUI

/// The single top-right identity entry. It opens the local profile menu rather
/// than Settings directly, so account data and Settings have one clear home.
struct ProfileBadge: View {
    @ObservedObject private var store = LocalProfileStore.shared
    @State private var showingMenu = false

    var body: some View {
        Button {
            showingMenu = true
        } label: {
            AvatarView(profile: store.profile, size: 38)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("个人资料、设置与数据")
        .accessibilityHint("打开本地头像、昵称和设置")
        .sheet(isPresented: $showingMenu) {
            ProfileMenuView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
