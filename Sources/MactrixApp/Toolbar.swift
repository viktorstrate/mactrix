import OSLog
import SwiftUI

struct ToolbarViewModifier: ViewModifier {
    @Environment(WindowState.self) var windowState

    func body(content: Content) -> some View {
        content
            .toolbar {
                Button {
                    Logger.viewCycle.info("Show pins")
                    windowState.showRoomPins()
                } label: {
                    Label("Show Pins", systemImage: "pin.circle")
                }
                .help("Show Pins")
                .disabled(windowState.selectedRoomId == nil)

                Button {
                    Logger.viewCycle.info("Show threads")
                    windowState.showRoomThreads()
                } label: {
                    Label("Show Threads", systemImage: "list.bullet.circle")
                }
                .help("Show Threads")
                .disabled(windowState.selectedRoomId == nil)

                if #unavailable(macOS 26), !windowState.inspectorVisible {
                    HStack {
                        Divider()
                    }
                }
            }
    }
}
