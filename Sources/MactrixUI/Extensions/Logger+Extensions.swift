import OSLog

extension Logger {
    private static let subsystem = "dk.qpqp.mactrix.mactrix-ui"

    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")
}
