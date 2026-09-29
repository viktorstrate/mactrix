import MatrixProtocols
import SwiftUI

public struct RoomEncryptionBadge: View {
    let state: EncryptionState

    public init(state: EncryptionState) {
        self.state = state
    }

    struct Badge {
        let label: String
        let icon: String
        let color: Color
    }

    var badge: Badge {
        switch state {
        case .encrypted:
            return Badge(label: "Encrypted", icon: "lock.fill", color: .green)
        case .notEncrypted:
            return Badge(label: "Not encrypted", icon: "lock.open.fill", color: .blue)
        case .unknown:
            return Badge(label: "Encryption unknown", icon: "questionmark", color: .gray)
        }
    }

    public var body: some View {
        Label(badge.label, systemImage: badge.icon)
            .font(.subheadline.bold())
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .foregroundStyle(badge.color.mix(with: .black, by: 0.1))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(badge.color.quaternary)
                // .stroke(badge.color.secondary)
            )
    }
}

#Preview {
    RoomEncryptionBadge(state: .encrypted)
    RoomEncryptionBadge(state: .notEncrypted)
    RoomEncryptionBadge(state: .unknown)
}
