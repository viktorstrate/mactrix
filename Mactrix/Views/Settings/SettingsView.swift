import SwiftUI
import MatrixRustSDK

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Account", systemImage: "person") {
                AccountSettingsView()
            }
            Tab("Appearance", systemImage: "eye") {
                Text("Appearance Settings")
            }
            Tab("Encryption", systemImage: "lock") {
                Text("Encryption Settings")
            }
        }
        .scenePadding()
        .frame(maxWidth: 450, minHeight: 200)
    }
}

#Preview {
    SettingsView()
        .environment(AppState.previewMock)
}
