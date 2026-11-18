import ContactLinking
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
    let contacts = ContactDirectory.shared
    let userID = userProfile.userId
    let matrixName = userProfile.displayName

    return Text(contacts.resolvedName(userID: userID, matrixName: matrixName))
      .foregroundStyle(Color(userID: userID))
      .lineLimit(1)
      .truncationMode(.tail)
      .help(contacts.matrixIdentityHelp(userID: userID, matrixName: matrixName) ?? userID)
  }
}
