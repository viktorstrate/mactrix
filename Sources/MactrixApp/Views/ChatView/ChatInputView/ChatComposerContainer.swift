import AppKit
import MatrixRustSDK

private final class ComposerDecorationView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@available(macOS 26.0, *)
private final class ComposerGlassView: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ChatComposerContainer: NSView {
  private static let horizontalInset: CGFloat = 16
  private static let sectionSpacing: CGFloat = 8
  private static let replyInset: CGFloat = 10
  private static let bottomSpacing: CGFloat = 10

  let editor = ComposerMentionTextView()
  let reply = MessageReplyPreviewView()
  let attachments = ComposerAttachmentPreviewStrip()
  let dropDestination = ComposerAttachmentDropDestination()

  @MainActor
  private struct Section {
    let view: NSView
    let measure: (CGFloat) -> CGFloat
    let heightConstraint: NSLayoutConstraint

    init(view: NSView, measure: @escaping (CGFloat) -> CGFloat) {
      self.view = view
      self.measure = measure
      heightConstraint = view.heightAnchor.constraint(equalToConstant: 0)
    }
  }

  private let stack = NSStackView()
  private let replyWrapper = NSView()
  private var sections: [Section] = []

  private let surface = ComposerDecorationView()
  private let highlight = ComposerDecorationView()
  private var glass: NSView?
  private var reduceTransparency = true
  private var replyDetails: EmbeddedEventDetails?
  var onWindowChanged: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true

    for view in [surface, stack, highlight] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }

    for view in [surface, highlight] {
      view.wantsLayer = true
      view.layer?.cornerRadius = 16
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
        view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
        view.topAnchor.constraint(equalTo: topAnchor),
        view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomSpacing),
      ])
    }

    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = Self.sectionSpacing
    stack.detachesHiddenViews = true
    stack.translatesAutoresizingMaskIntoConstraints = true
    stack.autoresizingMask = []

    reply.translatesAutoresizingMaskIntoConstraints = false
    replyWrapper.addSubview(reply)
    NSLayoutConstraint.activate([
      reply.leadingAnchor.constraint(
        equalTo: replyWrapper.leadingAnchor, constant: Self.replyInset),
      reply.trailingAnchor.constraint(
        equalTo: replyWrapper.trailingAnchor, constant: -Self.replyInset),
      reply.topAnchor.constraint(equalTo: replyWrapper.topAnchor),
      reply.bottomAnchor.constraint(equalTo: replyWrapper.bottomAnchor),
    ])
    replyWrapper.isHidden = true
    reply.isHidden = true
    attachments.isHidden = true
    sections = [
      Section(view: replyWrapper) { [weak self] width in
        guard let details = self?.replyDetails else { return 0 }
        return MessageReplyPreviewView.height(
          for: details, width: max(1, width - 2 * Self.replyInset))
      },
      Section(view: attachments) { _ in ComposerAttachmentPreviewStrip.height },
      Section(view: editor) { [weak self] width in self?.editor.height(for: width) ?? 0 },
    ]
    for section in sections {
      section.view.translatesAutoresizingMaskIntoConstraints = false
      stack.addArrangedSubview(section.view)
      section.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    updateSectionHeights(for: frame.width)
    editor.attachmentDropDestination = dropDestination
    registerForDraggedTypes(ComposerAttachmentInputAdapter.dragTypes)
    dropDestination.onHighlight = { [weak self] active in
      self?.highlight.layer?.backgroundColor =
        active
        ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor : nil
      self?.highlight.layer?.borderColor = NSColor.controlAccentColor.cgColor
      self?.highlight.layer?.borderWidth = active ? 2 : 0
    }
    updateAppearance(reduceTransparency: true)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    effectiveAppearance.performAsCurrentDrawingAppearance {
      updateAppearance(reduceTransparency: reduceTransparency)
    }
  }

  func updateAppearance(reduceTransparency: Bool) {
    self.reduceTransparency = reduceTransparency
    if #available(macOS 26.0, *), !reduceTransparency {
      if glass == nil {
        let effect = ComposerGlassView()
        effect.cornerRadius = 16
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect, positioned: .below, relativeTo: surface)
        NSLayoutConstraint.activate([
          effect.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
          effect.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
          effect.topAnchor.constraint(equalTo: surface.topAnchor),
          effect.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
        glass = effect
      }
      glass?.isHidden = false
      surface.layer?.backgroundColor = nil
      surface.layer?.borderWidth = 0
    } else {
      glass?.isHidden = true
      surface.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
      surface.layer?.borderColor = NSColor.separatorColor.cgColor
      surface.layer?.borderWidth = 1
    }
  }

  func setReply(details: EmbeddedEventDetails?) {
    replyDetails = details
    if let details { reply.configure(details: details) }
    reply.isHidden = details == nil
    replyWrapper.isHidden = reply.isHidden
    invalidateSizing()
  }

  func setAttachments(_ attachments: [ComposerAttachment]) {
    self.attachments.update(attachments: attachments)
    self.attachments.isHidden = attachments.isEmpty
    invalidateSizing()
  }

  private var topInset: CGFloat {
    sections.contains { $0.view !== editor && !$0.view.isHidden } ? Self.sectionSpacing : 0
  }

  private func measuredSections(for width: CGFloat) -> [(
    section: Section, height: CGFloat, spacingAfter: CGFloat
  )] {
    let contentWidth = max(1, width - 2 * Self.horizontalInset)
    let visible = sections.filter { !$0.view.isHidden }
    return visible.enumerated().map { index, section in
      let next = visible.dropFirst(index + 1).first
      // The editor supplies its own clickable inset; don't add an external gap above it.
      let spacing: CGFloat = next == nil || next?.view === editor ? 0 : Self.sectionSpacing
      return (section, section.measure(contentWidth), spacing)
    }
  }

  func height(for width: CGFloat) -> CGFloat {
    let measured = measuredSections(for: width)
    return ceil(
      measured.reduce(0) { $0 + $1.height + $1.spacingAfter } + topInset + Self.bottomSpacing)
  }

  private func updateSectionHeights(for width: CGFloat) {
    for section in sections where section.view.isHidden {
      section.heightConstraint.isActive = false
    }
    for (section, height, spacingAfter) in measuredSections(for: width) {
      stack.setCustomSpacing(spacingAfter, after: section.view)
      section.heightConstraint.constant = height
      section.heightConstraint.isActive = true
    }

  }

  func invalidateSizing() {
    updateSectionHeights(for: bounds.width)
    needsLayout = true
    invalidateIntrinsicContentSize()
    superview?.needsLayout = true
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: height(for: bounds.width))
  }

  override func layout() {
    updateSectionHeights(for: bounds.width)
    stack.frame = NSRect(
      x: Self.horizontalInset, y: Self.bottomSpacing,
      width: max(0, bounds.width - 2 * Self.horizontalInset),
      height: max(0, bounds.height - topInset - Self.bottomSpacing))
    super.layout()
  }

  override func setFrameSize(_ newSize: NSSize) {
    let changed = frame.width != newSize.width
    super.setFrameSize(newSize)
    if changed {
      needsLayout = true
      invalidateIntrinsicContentSize()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChanged?()
  }

  override var acceptsFirstResponder: Bool { true }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dropDestination.entered(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dropDestination.entered(sender)
  }
  override func draggingExited(_ sender: (any NSDraggingInfo)?) { dropDestination.exited() }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    dropDestination.operation(sender) == .copy
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    dropDestination.perform(sender)
  }
  override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { dropDestination.exited() }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
