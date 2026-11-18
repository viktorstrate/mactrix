import SwiftUI

public struct AppCommands: Commands {
  @FocusedValue(WindowState.self) private var windowState: WindowState?
  @AppStorage("fontSize") var fontSize: Int = 13

  public init() {}

  public var body: some Commands {
    SidebarCommands()
    InspectorCommands()
    TextEditingCommands()
    ToolbarCommands()

    about
    newTab
    createRoom
    quickNavigation
    fontSizeCommands
    conversationCommands
  }

  var about: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Mactrix") {
        let version = AppVersion(info: Bundle.main.infoDictionary ?? [:])
        NSApp.orderFrontStandardAboutPanel(options: [
          .applicationVersion: version.displayVersion,
          .version: version.build,
        ])
      }
    }
  }

  var newTab: some Commands {
    CommandGroup(after: .newItem) {
      Button(action: {
        guard
          let currentMainWindow = NSApp.orderedWindows.first(where: { window in
            window.identifier?.rawValue.starts(with: "main-AppWindow") ?? false
          })
        else {
          return
        }

        guard let windowController = currentMainWindow.windowController else {
          return
        }

        windowController.newWindowForTab(nil)
        if let newWindow = NSApp.keyWindow, currentMainWindow != newWindow {
          currentMainWindow.addTabbedWindow(newWindow, ordered: .above)
          newWindow.makeKeyAndOrderFront(nil)
        }
      }) {
        Text("New Tab")
      }
      .keyboardShortcut("t", modifiers: [.command])
    }
  }

  var quickNavigation: some Commands {
    CommandGroup(after: .newItem) {
      Button("Quick Navigation") {
        windowState?.quickNavigation.toggle()
      }
      .keyboardShortcut("k", modifiers: [.command])
      .disabled(windowState?.quickNavigation.isSignedIn != true)
    }
  }

  var createRoom: some Commands {
    CommandGroup(after: .newItem) {
      Self.createRoomButton(windowState: windowState)
    }
  }

  static func createRoomButton(windowState: WindowState?) -> some View {
    Button {
      windowState?.selectedScreen = .newRoom
    } label: {
      Label("Create room", systemImage: "plus.bubble")
    }
    .help("Create a new room")
    .keyboardShortcut("N", modifiers: [.command, .shift])
    .disabled(windowState != nil)
  }

  var conversationCommands: some Commands {
    CommandMenu("Conversation") {
      let selection = windowState?.conversationSelection
      let filenames = selection?.downloadFilenames ?? []

      messageActionButton("Add Reaction", action: .reactionPicker)
        .keyboardShortcut("r", modifiers: [.command, .shift])
      messageActionButton("Reply", action: .reply)
        .keyboardShortcut("r", modifiers: [.command])
      messageActionButton("Reply in Thread", action: .replyInThread)
        .keyboardShortcut("r", modifiers: [.command, .control])
      messageActionButton("Edit Message", action: .edit)
        .keyboardShortcut("e", modifiers: [.command, .shift])
      messageActionButton(
        selection?.isPinned == true ? "Unpin Message" : "Pin Message", action: .pin
      )
      .keyboardShortcut("p", modifiers: [.command, .option])

      Divider()

      if filenames.count > 1 {
        Menu("Download to File…") {
          ForEach(filenames.indices, id: \.self) { index in
            messageActionButton(verbatim: filenames[index], action: .downloadToFile(index))
              .keyboardShortcut(
                index == 0 ? KeyboardShortcut("s", modifiers: [.command, .shift]) : nil)
          }
        }
        .disabled(selection?.canPerform(.downloadToFile(0)) != true)
      } else {
        messageActionButton("Download to File…", action: .downloadToFile(0))
          .keyboardShortcut("s", modifiers: [.command, .shift])
          .disabled(filenames.isEmpty)
      }
      messageActionButton("Copy Message Link", action: .copyMessageLink)
        .keyboardShortcut("c", modifiers: [.command, .shift])
      messageActionButton("Show Source", action: .showSource)
        .keyboardShortcut("u", modifiers: [.command, .option])

      Divider()

      messageActionButton("Delete Message", action: .delete)
        .keyboardShortcut(.delete, modifiers: [.command, .shift])
    }
  }

  private func messageActionButton(
    _ title: LocalizedStringKey, action: MessageHoverOverlayView.Action
  ) -> some View {
    messageActionButton(label: Text(title), action: action)
  }

  private func messageActionButton(
    verbatim title: String, action: MessageHoverOverlayView.Action
  ) -> some View {
    messageActionButton(label: Text(verbatim: title), action: action)
  }

  @ViewBuilder
  private func messageActionButton(
    label: Text, action: MessageHoverOverlayView.Action
  ) -> some View {
    let selection = windowState?.conversationSelection

    Button {
      selection?.perform(action)
    } label: {
      label
    }
    .disabled(selection?.canPerform(action) != true)
  }

  var fontSizeCommands: some Commands {
    CommandGroup(after: .toolbar) {
      Button {
        fontSize += 1
      } label: {
        Text("Make Text Bigger")
      }
      .keyboardShortcut("+", modifiers: [.command])
      .disabled(fontSize >= 24)

      Button {
        fontSize = 13
      } label: {
        Text("Make Text Normal Size")
      }
      .keyboardShortcut("0", modifiers: [.command])
      .disabled(fontSize == 13)

      Button {
        fontSize -= 1

      } label: {
        Text("Make Text Smaller")
      }
      .keyboardShortcut("-", modifiers: [.command])
      .disabled(fontSize <= 8)
    }
  }
}
