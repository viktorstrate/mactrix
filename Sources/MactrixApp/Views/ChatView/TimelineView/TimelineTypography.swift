import AppKit

/// Shared metrics for both timeline rendering and row measurement.
@MainActor
enum TimelineTypography {
  static var fontSize: CGFloat {
    CGFloat(UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13)
  }

  static var timestampColumnWidth: CGFloat { scaled(48) }

  static func scaled(_ size: CGFloat) -> CGFloat {
    size * fontSize / 13
  }
}
