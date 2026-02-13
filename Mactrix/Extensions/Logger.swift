import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let matrixClient = Logger(subsystem: subsystem, category: "matrix-client")
    static let windowState = Logger(subsystem: subsystem, category: "window-state")

    static let liveRoom = Logger(subsystem: subsystem, category: "live-room")
    static let liveSpaceService = Logger(subsystem: subsystem, category: "live-space-service")
    static let liveSpaceRoomList = Logger(subsystem: subsystem, category: "live-space-room-list")
    static let liveTimeline = Logger(subsystem: subsystem, category: "live-timeline")
    static let SidebarRoom = Logger(subsystem: subsystem, category: "sidebar-room")

    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")

    static let notification = Logger(subsystem: subsystem, category: "notification")
}
