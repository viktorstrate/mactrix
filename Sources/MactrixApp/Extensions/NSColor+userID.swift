import AppKit

public extension NSColor {
    convenience init(userID: String) {
        unsafe self.init(named: String(
            format: "Username%02d",
            userID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 16 + 1
        ))!
    }
}
