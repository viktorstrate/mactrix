import Models
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

    var kindName: String {
        switch preview.roomKind {
        case .space:
            "space"
        default:
            "room"
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 15) {
            AvatarImage(avatarUrl: preview.avatarUrl, imageLoader: imageLoader)
                .frame(width: 72, height: 72)
                .clipShape(.circle)

            VStack(alignment: .leading) {
                Text(preview.name ?? "Unknown name")
                    .font(.title)
                    .textSelection(.enabled)

                if let alias = preview.canonicalAlias {
                    Text(alias)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("^[\(preview.numJoinedMembers) member](inflect: true)")
                        .modifier(SmallBadgeModifier(color: .green))
                        .help("^[\(preview.numJoinedMembers) member](inflect: true) have joined this \(kindName)")

                    switch preview.joinRuleInfo {
                    case .public:
                        Label("Public", systemImage: "globe")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("Everyone can join this room")
                    case .invite:
                        Label("Invite only", systemImage: "lock")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("You need an invitation to join this \(kindName)")
                    case .knock where preview.userMembership != .knocked:
                        Label("Knock", systemImage: "hand.wave")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("Send a request to join the \(kindName)")
                    default:
                        EmptyView()
                    }

                    switch preview.userMembership {
                    case .invited:
                        Label("Invited", systemImage: "envelope.badge")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("You have been invited to join this \(kindName)")
                    case .joined:
                        Label("Joined", systemImage: "checkmark.square.fill")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("You are a member of this \(kindName)")
                    case .knocked:
                        Label("Knocked", systemImage: "envelope")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("You have requested to join this \(kindName)")
                    case .banned:
                        Label("Banned", systemImage: "exclamationmark.square")
                            .modifier(SmallBadgeModifier(color: .gray))
                            .help("You are banned from this \(kindName)")
                    default:
                        EmptyView()
                    }

                    switch preview.roomKind {
                    case .space:
                        Text("Space").modifier(SmallBadgeModifier(color: .blue))
                    // case .room:
                    //    Text("Room").modifier(SmallBadgeModifier(color: .blue))
                    case let .custom(value: value):
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
                    Button("Join \(kindName)") {
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

                        Text("Joining \(kindName)...")
                    }
                    .foregroundStyle(.secondary)
                    .opacity(actionLoading ? 1 : 0)
                } else {
                    Button("Visit \(kindName)") {
                        actions?.visitRoom()
                    }
                    .disabled(actions == nil || actionLoading)
                }
            case .knock where preview.userMembership != .knocked:
                Button("Request to join \(kindName)") {
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

                    Text("Requesting to join \(kindName)...")
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

                LabeledContent(content: {
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
    RoomPreviewView(preview: MockRoomPreviewInfo(), imageLoader: nil, actions: MockRoomPreviewActions())
        .frame(width: 400, height: 600)
}
