import SwiftUI

enum SettingsTab: Hashable {
  case account, appearance, sessions
}

public struct SettingsView: View {
  @State private var selection = SettingsTab.account

  public init() {}

  @ViewBuilder
  var tabView: some View {
    TabView(selection: $selection.animation()) {
      Tab("Account", systemImage: "person", value: .account) {
        AccountSettingsView().frame(width: 620, height: 500)
      }
      Tab("Appearance", systemImage: "eye", value: .appearance) {
        AppearanceSettingsView().frame(width: 620, height: 500)
      }
      Tab("Sessions", systemImage: "desktopcomputer.and.macbook", value: .sessions) {
        SessionsSettingsView().frame(width: 620, height: 500)
      }
    }
  }

  public var body: some View {
    if #available(macOS 26.0, *) {
      tabView.windowResizeAnchor(.top)
    } else {
      tabView
    }
  }
}
