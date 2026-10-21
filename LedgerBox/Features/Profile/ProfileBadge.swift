import SwiftUI

/// The single local-identity entry in the Home header's trailing corner. It
/// opens the local profile menu; there is no third-party sign-in.
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
        .accessibilityLabel("本地个人资料")
        .accessibilityHint("打开本地头像与昵称；不上传，不登录第三方")
        .sheet(isPresented: $showingMenu) {
            ProfileMenuView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
