import MatrixProtocols
import SwiftUI

struct Username<Profile: UserProfile>: View {
  var userProfile: Profile
  var isSelectable = true

  var body: some View {
    if isSelectable {
      label.textSelection(.enabled)
    } else {
      label.textSelection(.disabled)
    }
  }

  private var label: some View {
    Text(userProfile.displayName ?? userProfile.userId).foregroundStyle(
      Color(userID: userProfile.userId)
    )
    .lineLimit(1)
    .truncationMode(.tail)
    .help(userProfile.userId)
  }
}
