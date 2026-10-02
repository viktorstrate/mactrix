import OSLog

extension Logger {
  private static let subsystem = "dk.qpqp.mactrix.mactrix-app"

  static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")
  static let matrixClient = Logger(subsystem: subsystem, category: "matrix-client")
  static let windowState = Logger(subsystem: subsystem, category: "window-state")
  static let timelineTableView = Logger(subsystem: subsystem, category: "timeline-table-view")
  static let composerAttachment = Logger(subsystem: "com.mactrix.app", category: "composer-attachment")
}
