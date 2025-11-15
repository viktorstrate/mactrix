import Foundation

@MainActor
@Observable final class WindowState {
    var selectedRoom: SelectedRoom? = nil
}
