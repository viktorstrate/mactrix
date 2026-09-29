import SwiftUI

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            Tab("Account", systemImage: "person") {
                AccountSettingsView()
            }
            Tab("Appearance", systemImage: "eye") {
                AppearanceSettingsView()
            }
            Tab("Sessions", systemImage: "desktopcomputer.and.macbook") {
                SessionsSettingsView()
            }
        }
        .scenePadding()
        .frame(maxWidth: 450, minHeight: 200)
    }
}
