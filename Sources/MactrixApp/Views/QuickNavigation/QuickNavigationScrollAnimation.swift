import AppKit
import QuartzCore

/// A critically damped spring that preserves velocity when its destination changes.
@MainActor class QuickNavigationScrollAnimation {
  private static let angularFrequency: CGFloat = 28
  private static let completionDistance: CGFloat = 0.25
  private static let completionVelocity: CGFloat = 2

  private let scrollView: NSScrollView
  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval = 0
  private var targetY: CGFloat = 0
  private var velocityY: CGFloat = 0

  init(scrollView: NSScrollView) {
    self.scrollView = scrollView
    NotificationCenter.default.addObserver(
      self, selector: #selector(cancel),
      name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
  }

  func reveal(row: Int, in tableView: NSTableView, padding: CGFloat) {
    guard row >= 0, row < tableView.numberOfRows else {
      cancel()
      return
    }
    assert(
      tableView.enclosingScrollView === scrollView,
      "The animation's scroll view must enclose the table view."
    )

    let clipView = scrollView.contentView
    let visibleRect = clipView.bounds
    let rowRect = tableView.convert(tableView.rect(ofRow: row), to: clipView.documentView)
      .insetBy(dx: 0, dy: -padding)
    var destination = visibleRect.origin
    if rowRect.minY < visibleRect.minY {
      destination.y = rowRect.minY
    } else if rowRect.maxY > visibleRect.maxY {
      destination.y = rowRect.maxY - visibleRect.height
    }
    var destinationBounds = visibleRect
    destinationBounds.origin = destination
    let nextY = clipView.constrainBoundsRect(destinationBounds).origin.y
    targetY = nextY
    // Retargeting preserves both the running clock and the spring's current velocity.
    guard displayLink == nil, nextY != visibleRect.minY else { return }
    lastTimestamp = CACurrentMediaTime()
    let link = tableView.displayLink(target: self, selector: #selector(updateScrollPosition))
    displayLink = link
    link.add(to: .main, forMode: .common)
  }

  @objc private func updateScrollPosition() {
    let now = CACurrentMediaTime()
    let elapsed = now - lastTimestamp
    lastTimestamp = now

    let clipView = scrollView.contentView
    var origin = clipView.bounds.origin
    let elapsedTime = CGFloat(elapsed)
    let frequency = Self.angularFrequency
    let displacement = origin.y - targetY
    let coefficient = velocityY + frequency * displacement
    let decay = exp(-frequency * elapsedTime)
    // Exact critical-damping solution stays stable across refresh rates and delayed frames.
    let nextDisplacement = (displacement + coefficient * elapsedTime) * decay
    velocityY = (velocityY - frequency * coefficient * elapsedTime) * decay
    let finished =
      abs(nextDisplacement) <= Self.completionDistance
      && abs(velocityY) <= Self.completionVelocity
    origin.y = finished ? targetY : targetY + nextDisplacement
    clipView.scroll(to: origin)
    scrollView.reflectScrolledClipView(clipView)
    if finished { cancel() }
  }

  @objc func cancel() {
    displayLink?.invalidate()
    displayLink = nil
    velocityY = 0
  }
}
