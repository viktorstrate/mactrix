import SwiftUI

extension Color {
  public init(userID: String) {
    self.init(userAvatarColorName(userID: userID))
  }
}
