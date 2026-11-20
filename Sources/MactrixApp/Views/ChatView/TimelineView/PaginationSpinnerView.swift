import AppKit

final class PaginationSpinnerRowView: NSView {
  static let rowHeight: CGFloat = 48

  private let spinner = NSProgressIndicator()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    spinner.style = .spinning
    spinner.isIndeterminate = true
    spinner.controlSize = .regular  // measures 32 x 32 points
    spinner.translatesAutoresizingMaskIntoConstraints = false
    addSubview(spinner)

    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { return nil }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
    }
  }
}
