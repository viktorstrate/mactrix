import OSLog

extension Logger {
  private static let subsystem = "dk.qpqp.mactrix.matrix-integration"

  static let matrixClient = Logger(subsystem: subsystem, category: "matrix-client")
  static let liveRoom = Logger(subsystem: subsystem, category: "live-room")
  static let liveSpaceRoomList = Logger(subsystem: subsystem, category: "live-space-room-list")
  static let liveSpaceService = Logger(subsystem: subsystem, category: "live-space-service")
  static let liveTimeline = Logger(subsystem: subsystem, category: "live-timeline")
  static let sidebarRoom = Logger(subsystem: subsystem, category: "sidebar-room")
  static let notification = Logger(subsystem: subsystem, category: "notification")
}
