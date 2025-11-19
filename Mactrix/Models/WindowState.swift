import Foundation
import SwiftUI

@MainActor
@Observable final class WindowState {
    var selectedScreen: SelectedScreen = .none

    // @SceneStorage("MainView.selectedRoomId")
    var selectedRoomId: String?

    // @SceneStorage("MainView.inspectorVisible")
    var inspectorVisible: Bool = false

    var searchQuery: String = ""
    var searchTokens: [SearchToken] = []
    var searchFocused: Bool = false

    var inspectorOrSearchActive: Binding<Bool> {
        Binding(
            get: { self.inspectorVisible || self.searchFocused },
            set: { self.inspectorVisible = $0 }
        )
    }
}

enum SearchToken: Hashable, Identifiable {
    case users, rooms, spaces, messages

    var id: Self { self }
}
