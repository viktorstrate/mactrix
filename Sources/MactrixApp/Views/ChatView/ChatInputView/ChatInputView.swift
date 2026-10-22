import AppKit
import MatrixIntegration
import MatrixRustSDK
import SwiftUI

struct ChatInputView: NSViewControllerRepresentable {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @AppStorage("fontSize") private var fontSize = 13
  let room: Room
  let timeline: LiveTimeline
  let composer: ChatComposerState

  func makeNSViewController(context: Context) -> ChatInputViewController {
    ChatInputViewController(room: room, timeline: timeline, composer: composer)
  }

  func updateNSViewController(_ controller: ChatInputViewController, context: Context) {
    controller.update(fontSize: fontSize, reduceTransparency: reduceTransparency)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsViewController: ChatInputViewController,
    context: Context
  ) -> CGSize? {
    let width = proposal.width ?? 400
    return CGSize(width: width, height: nsViewController.container.height(for: width))
  }

  static func dismantleNSViewController(_ controller: ChatInputViewController, coordinator: ()) {
    controller.tearDown()
  }
}

/// Shared routing and highlight state for both native destinations.
@MainActor
final class ComposerAttachmentDropDestination {
  var enabled = false
  var onHighlight: ((Bool) -> Void)?
  var onDrop: ((NSPasteboard) -> Bool)?

  func recognizes(_ sender: any NSDraggingInfo) -> Bool {
    ComposerAttachmentInputAdapter.canImportAttachments(from: sender.draggingPasteboard)
  }

  func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
    ComposerAttachmentInputAdapter.attachmentOperation(
      from: sender.draggingPasteboard, sourceOperations: sender.draggingSourceOperationMask,
      enabled: enabled)
  }

  func entered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let result = operation(sender)
    onHighlight?(result == .copy)
    return result
  }

  func exited() {
    onHighlight?(false)
  }

  func perform(_ sender: any NSDraggingInfo) -> Bool {
    onHighlight?(false)
    guard operation(sender) == .copy else { return false }
    return onDrop?(sender.draggingPasteboard) ?? false
  }
}

private final class ComposerDecorationView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@available(macOS 26.0, *)
private final class ComposerGlassView: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ChatComposerContainer: NSView {
  private static let horizontalInset: CGFloat = 16
  private static let verticalInset: CGFloat = 0
  private static let bottomSpacing: CGFloat = 10

  let editor = DynamicTextView()
  let reply = MessageReplyPreviewView()
  let attachments = ComposerAttachmentPreviewStrip()
  let dropDestination = ComposerAttachmentDropDestination()
  private var sectionConstraints: [NSLayoutConstraint] = []
  private var sectionVisibility: [Bool] = []
  private let surface = ComposerDecorationView()
  private let highlight = ComposerDecorationView()
  private var glass: NSView?
  private var reduceTransparency = true
  private var replyHeight: NSLayoutConstraint!
  private var editorHeight: NSLayoutConstraint!
  var replyDetails: EmbeddedEventDetails?
  var onWindowChanged: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true

    for view in [surface, reply, attachments, editor, highlight] {
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

    for view in [reply, attachments, editor] {
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
        view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
      ])
    }

    reply.isHidden = true
    attachments.isHidden = true
    replyHeight = reply.heightAnchor.constraint(equalToConstant: 60)
    editorHeight = editor.heightAnchor.constraint(equalToConstant: 36)
    NSLayoutConstraint.activate([
      editor.bottomAnchor.constraint(
        equalTo: bottomAnchor, constant: -(Self.verticalInset + Self.bottomSpacing)),
      replyHeight, editorHeight,
      attachments.heightAnchor.constraint(equalToConstant: ComposerAttachmentPreviewStrip.height),
    ])
    updateSectionConstraints()
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

  func height(for width: CGFloat) -> CGFloat {
    let contentWidth = max(1, width - 2 * Self.horizontalInset)
    var height = editor.height(for: contentWidth) + 2 * Self.verticalInset + Self.bottomSpacing
    if let replyDetails {
      height += MessageReplyPreviewView.height(for: replyDetails, width: contentWidth) + 8
    }
    if !attachments.isHidden { height += ComposerAttachmentPreviewStrip.height + 8 }
    return ceil(height)
  }

  private func updateSectionConstraints() {
    let visibility = [!reply.isHidden, !attachments.isHidden]
    guard visibility != sectionVisibility else { return }
    sectionVisibility = visibility
    NSLayoutConstraint.deactivate(sectionConstraints)
    sectionConstraints = []
    var previous: NSView?
    for section in [reply, attachments, editor] {
      if section.isHidden {
        sectionConstraints.append(
          section.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset))
      } else {
        sectionConstraints.append(
          section.topAnchor.constraint(
            equalTo: previous?.bottomAnchor ?? topAnchor,
            constant: previous == nil ? Self.verticalInset : 8))
        previous = section
      }
    }
    NSLayoutConstraint.activate(sectionConstraints)
  }

  func invalidateSizing() {
    updateSectionConstraints()
    needsLayout = true
    invalidateIntrinsicContentSize()
    superview?.invalidateIntrinsicContentSize()
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: height(for: bounds.width))
  }

  override func layout() {
    let width = max(1, bounds.width - 2 * Self.horizontalInset)
    editorHeight.constant = editor.height(for: width)
    if let replyDetails {
      replyHeight.constant = MessageReplyPreviewView.height(for: replyDetails, width: width)
    }
    super.layout()
  }

  override func setFrameSize(_ newSize: NSSize) {
    let changed = frame.width != newSize.width
    super.setFrameSize(newSize)
    if changed { invalidateSizing() }
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
