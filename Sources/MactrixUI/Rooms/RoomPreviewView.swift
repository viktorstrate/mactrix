import MatrixProtocols
import OSLog
import SwiftUI

struct SmallBadgeModifier: ViewModifier {
  let color: Color

  func body(content: Content) -> some View {
    content
      .foregroundStyle(color.mix(with: Color(NSColor(.primary)), by: 0.3))
      .padding(.vertical, 5)
      .padding(.horizontal, 8)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(color.opacity(0.2))
      )
  }
}

@MainActor
public protocol RoomPreviewActions {
  func joinRoom() async throws
  func knockRoom() async throws
  func visitRoom()
}

struct MockRoomPreviewActions: RoomPreviewActions {
  func joinRoom() async throws {}
  func knockRoom() async throws {}
  func visitRoom() {}
}

public struct RoomPreviewView<RoomPreview: RoomPreviewInfo>: View {
  let preview: RoomPreview
  let imageLoader: ImageLoader?
  let actions: RoomPreviewActions?

  @State var actionLoading: Bool = false

  public init(preview: RoomPreview, imageLoader: ImageLoader?, actions: RoomPreviewActions?) {
    self.preview = preview
    self.imageLoader = imageLoader
    self.actions = actions
  }

  /// Picks the variant for the previewed kind, so each sentence can be translated as a whole.
  func kindText(room: LocalizedStringKey, space: LocalizedStringKey) -> LocalizedStringKey {
    switch preview.roomKind {
    case .space: space
    default: room
    }
  }

  var header: some View {
    HStack(alignment: .top, spacing: 15) {
      AvatarImage(
        userID: preview.roomId, kind: .room, displayName: preview.name,
        avatarUrl: preview.avatarUrl, imageLoader: imageLoader
      )
      .frame(width: 72, height: 72)

      VStack(alignment: .leading) {
        Text(preview.name ?? String(localized: "Unknown name"))
          .font(.title)
          .textSelection(.enabled)

        if let alias = preview.canonicalAlias {
          Text(alias)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        HStack {
          Text("\(preview.numJoinedMembers) members")
            .modifier(SmallBadgeModifier(color: .green))
            .help(
              kindText(
                room: "\(preview.numJoinedMembers) members have joined this room",
                space: "\(preview.numJoinedMembers) members have joined this space"))

          switch preview.joinRuleInfo {
          case .public:
            Label("Public", systemImage: "globe")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "Everyone can join this room", space: "Everyone can join this space"))
          case .invite:
            Label("Invite only", systemImage: "lock")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "You need an invitation to join this room",
                  space: "You need an invitation to join this space"))
          case .knock where preview.userMembership != .knocked:
            Label("Knock", systemImage: "hand.wave")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "Send a request to join the room", space: "Send a request to join the space"
                ))
          default:
            EmptyView()
          }

          switch preview.userMembership {
          case .invited:
            Label("Invited", systemImage: "envelope.badge")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "You have been invited to join this room",
                  space: "You have been invited to join this space"))
          case .joined:
            Label("Joined", systemImage: "checkmark.square.fill")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "You are a member of this room", space: "You are a member of this space"))
          case .knocked:
            Label("Knocked", systemImage: "envelope")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "You have requested to join this room",
                  space: "You have requested to join this space"))
          case .banned:
            Label("Banned", systemImage: "exclamationmark.square")
              .modifier(SmallBadgeModifier(color: .gray))
              .help(
                kindText(
                  room: "You are banned from this room", space: "You are banned from this space"))
          default:
            EmptyView()
          }

          switch preview.roomKind {
          case .space:
            Text("Space").modifier(SmallBadgeModifier(color: .blue))
          // case .room:
          //    Text("Room").modifier(SmallBadgeModifier(color: .blue))
          case .custom(let value):
            Text(value).modifier(SmallBadgeModifier(color: .blue))
          default:
            EmptyView()
          }
        }
      }
    }
  }

  @ViewBuilder
  var actionButton: some View {
    HStack {
      switch preview.joinRuleInfo {
      case .public, .other, nil:
        if preview.userMembership != .joined {
          Button(kindText(room: "Join room", space: "Join space")) {
            guard let actions = self.actions else { return }
            Task {
              actionLoading = true
              defer { actionLoading = false }

              do {
                try await actions.joinRoom()
              } catch {
                Logger.viewCycle.error("Failed to join room \(error)")
              }
            }
          }
          .disabled(actions == nil || actionLoading)

          HStack(spacing: 0) {
            ProgressView()
              .scaleEffect(0.5)

            Text(kindText(room: "Joining room…", space: "Joining space…"))
          }
          .foregroundStyle(.secondary)
          .opacity(actionLoading ? 1 : 0)
        } else {
          Button(kindText(room: "Visit room", space: "Visit space")) {
            actions?.visitRoom()
          }
          .disabled(actions == nil || actionLoading)
        }
      case .knock where preview.userMembership != .knocked:
        Button(kindText(room: "Request to join room", space: "Request to join space")) {
          guard let actions = self.actions else { return }
          Task {
            actionLoading = true
            defer { actionLoading = false }

            do {
              try await actions.knockRoom()
            } catch {
              Logger.viewCycle.error("Failed to knock room \(error)")
            }
          }
        }
        .disabled(actions == nil || actionLoading)

        HStack(spacing: 0) {
          ProgressView()
            .scaleEffect(0.5)

          Text(kindText(room: "Requesting to join room…", space: "Requesting to join space…"))
        }
        .foregroundStyle(.secondary)
        .opacity(actionLoading ? 1 : 0)
      case .knock where preview.userMembership == .knocked:
        Button("Join request sent") {}
          .disabled(true)
      default:
        EmptyView()
      }
    }
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        actionButton

        Divider()

        if let topic = preview.topic {
          Text(topic.formatAsMarkdown)
            .textSelection(.enabled)
          Divider()
        }

        LabeledContent(
          content: {
            Text(preview.roomId)
              .textSelection(.enabled)
          }, label: { Text("Room ID:").bold() })

        Spacer()
      }
      .padding(.horizontal)
      .padding(.vertical, 30)
    }
  }
}

#Preview {
  RoomPreviewView(
    preview: MockRoomPreviewInfo(), imageLoader: nil, actions: MockRoomPreviewActions()
  )
  .frame(width: 400, height: 600)
}
