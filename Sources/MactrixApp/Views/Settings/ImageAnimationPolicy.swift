import Foundation

enum ImageAnimationPolicy: String, CaseIterable {
  case always
  case onHover
  case never

  static let defaultsKey = "imageAnimationPolicy"

  var title: String {
    switch self {
    case .always: String(localized: "Always")
    case .onHover: String(localized: "On Hover")
    case .never: String(localized: "Never")
    }
  }

  func shouldAnimate(isKeyWindow: Bool, isApplicationActive: Bool, isHovered: Bool) -> Bool {
    guard isKeyWindow, isApplicationActive else { return false }
    switch self {
    case .always: return true
    case .onHover: return isHovered
    case .never: return false
    }
  }
}
