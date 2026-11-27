/// What the Mac's current network connection allows.
public struct NetworkConditions: Sendable, Equatable {
  /// Whether there is a connection at all.
  public var isAvailable: Bool
  /// Whether the connection is one the user may pay for, such as a phone's hotspot.
  public var isExpensive: Bool
  /// Whether the user turned on Low Data Mode for the connection.
  public var isConstrained: Bool

  public init(isAvailable: Bool = true, isExpensive: Bool = false, isConstrained: Bool = false) {
    self.isAvailable = isAvailable
    self.isExpensive = isExpensive
    self.isConstrained = isConstrained
  }

  /// Whether requests that can wait should be kept to a minimum on this connection.
  public var isSavingData: Bool { isExpensive || isConstrained }
}
