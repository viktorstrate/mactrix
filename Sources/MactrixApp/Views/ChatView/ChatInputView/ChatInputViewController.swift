import AppKit
import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import OSLog
import Observation
import QuickLookUI

@MainActor
final class ChatInputViewController: NSViewController, NSTextViewDelegate {
  let room: Room
  let timeline: LiveTimeline
  let composer: ChatComposerState
  private let container = ChatComposerContainer()
  var composerView: ChatComposerContainer {
    loadViewIfNeeded()
    return container
  }

  private lazy var editorSession = ComposerEditorSession(
    editor: container.editor, composer: composer)

  private var previewAttachments: [ComposerAttachment] = []
  private var initialPreviewItemIndex = 0
  var previewAttachmentID: ComposerAttachment.ID? {
    var index = initialPreviewItemIndex
    if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.currentController as AnyObject? === self
    {
      index = panel.currentPreviewItemIndex
    }
    guard previewAttachments.indices.contains(index) else { return nil }
    return previewAttachments[index].id
  }

  private var fontSize = 13
  private var revision: Int?
  private var wasDraftLoaded = false
  private var draftLoadTask: Task<Void, Never>?
  private var draftSaveTask: Task<Void, Never>?

  private var actionTasks: [UUID: Task<Void, Never>] = [:]

  init(
    room: Room, timeline: LiveTimeline, composer: ChatComposerState,
    imageLoader: ImageLoader? = nil,
    avatarURLLookup: ComposerMentionTextView.AvatarURLLookup? = nil
  ) {
    self.room = room
    self.timeline = timeline
    self.composer = composer
    super.init(nibName: nil, bundle: nil)
    container.editor.imageLoader = imageLoader
    container.editor.avatarURLLookup = avatarURLLookup
    container.editor.mentionCandidateProvider = { [weak self] in
      self?.timeline.room.members ?? []
    }
  }

  override func loadView() {
    view = container
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let editor = container.editor
    editor.allowsUndo = true
    editor.backgroundColor = .clear
    editor.drawsBackground = false
    editor.textContainerInset = DynamicTextView.padding
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    unsafe editor.textContainer?.widthTracksTextView = true
    editor.delegate = self
    editor.onSubmit = { [weak self] in self?.submit() }
    editor.onCanPasteAttachments = ComposerAttachmentInputAdapter.canImportAttachments
    editor.onAttachmentPaste = { [weak self] pasteboard in
      self?.importAttachments(from: pasteboard) ?? false
    }

    container.dropDestination.onDrop = { [weak self] pasteboard in
      self?.importAttachments(from: pasteboard) ?? false
    }
    container.reply.onClick = { [weak self] in self?.composer.cancelReply() }
    container.attachments.onRemove = { [weak self] id in self?.removeAttachment(id: id) }
    container.attachments.onPreview = { [weak self] id in self?.showPreview(id: id) }
    container.onWindowChanged = { [weak self] in self?.requestFocus() }
    editor.onWindowChanged = { [weak self] in self?.requestFocus() }
    observeState()
  }

  func update(fontSize: Int, reduceTransparency: Bool) {
    loadViewIfNeeded()
    self.fontSize = fontSize
    container.updateAppearance(reduceTransparency: reduceTransparency)
    synchronizeEditor()
  }

  private func observeState() {
    withObservationTracking {
      _ = composer.text
      _ = composer.replyTarget
      _ = composer.attachments
      _ = composer.isDraftLoaded
      _ = composer.focusRequest
      _ = composer.draftRevision
      _ = timeline.timeline
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.observeState()
      }
    }

    synchronizeEditor()
    if timeline.timeline != nil, !composer.isDraftLoaded, draftLoadTask == nil {
      let room = room
      let timeline = timeline
      let composer = composer
      draftLoadTask = Task { await composer.loadDraft(room: room, timeline: timeline) }
    }
    if revision != composer.draftRevision || wasDraftLoaded != composer.isDraftLoaded {
      revision = composer.draftRevision
      wasDraftLoaded = composer.isDraftLoaded
      scheduleDraftSave()
    }
  }

  /// Only replace externally changed text; ordinary editing preserves selection and undo.
  func synchronizeEditor() {
    editorSession.synchronize(
      text: composer.text, enabled: composer.isDraftLoaded,
      placeholder: "Message \(room.displayName() ?? "room")", fontSize: fontSize)
    let enabled = composer.isDraftLoaded
    container.dropDestination.enabled = enabled
    if let target = composer.replyTarget {
      let details = EmbeddedEventDetails.ready(
        content: target.content, sender: target.sender, senderProfile: target.senderProfile,
        timestamp: target.timestamp, eventOrTransactionId: target.eventOrTransactionId)
      container.setReply(details: details)
    } else {
      container.setReply(details: nil)
    }
    synchronizePreviewAttachments()
    container.setAttachments(composer.attachments)
    requestFocus()
  }

  func textDidChange(_ notification: Notification) {
    guard container.editor.isEditable else { return }
    editorSession.textDidChange()
    container.invalidateSizing()
  }

  func requestFocus() {
    editorSession.requestFocus(composer.focusRequest)
  }

  private func scheduleDraftSave() {
    draftSaveTask?.cancel()
    guard composer.isDraftLoaded else { return }
    let composer = composer
    let room = room
    let timeline = timeline
    draftSaveTask = Task {
      await composer.saveDraft(room: room, timeline: timeline)
      guard !Task.isCancelled, !composer.text.isEmpty else { return }
      do { try await room.typingNotice(isTyping: true) } catch {
        Logger.viewCycle.warning("Failed to send typing notice: \(error)")
      }
    }
  }

  private func submit() {
    guard composer.isDraftLoaded, let inner = timeline.timeline else { return }
    let snapshot = composer.captureSubmission(content: container.editor.textContent)
    let id = UUID()
    let composer = composer
    actionTasks[id] = Task { [weak self] in
      await composer.sendMessage(timeline: inner, snapshot: snapshot)
      self?.actionTasks[id] = nil
    }
  }

  @discardableResult
  func importAttachments(from pasteboard: NSPasteboard) -> Bool {
    guard composer.isDraftLoaded else { return false }
    let inputs = ComposerAttachmentInputAdapter.inputs(from: pasteboard, captureFiles: true)
    guard !inputs.isEmpty else { return false }
    let id = UUID()
    actionTasks[id] = Task { [weak self] in
      var attachments: [ComposerAttachment] = []
      // Finish consuming captured inputs even after cancellation so owned files are cleaned up.
      for input in inputs {
        do { attachments.append(try await ComposerAttachmentImporter.importInput(input)) } catch {
          Logger.composerView.error("Unable to import attachment: \(error)")
        }
      }
      guard !Task.isCancelled, let self else {
        for attachment in attachments where attachment.storageOwnership == .appOwnedTemporaryFile {
          try? ComposerAttachmentImporter.cleanupTemporaryAttachment(attachment)
        }
        return
      }
      composer.addAttachments(attachments)
      if !attachments.isEmpty { composer.requestTextFocus() }
      actionTasks[id] = nil
    }
    return true
  }

  func removeAttachment(id: ComposerAttachment.ID) {
    if previewAttachmentID == id { closePreview() }
    composer.removeAttachment(id: id)
  }

  func tearDown() {
    draftLoadTask?.cancel()
    draftLoadTask = nil
    draftSaveTask?.cancel()
    draftSaveTask = nil
    editorSession.tearDown()
    container.editor.mentionAutocomplete.reset()
    container.editor.mentionCandidateProvider = nil
    container.editor.cancelAvatarLookups()
    actionTasks.values.forEach { $0.cancel() }
    actionTasks.removeAll()
    closePreview()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension ChatInputViewController: @preconcurrency QLPreviewPanelDataSource {
  func showPreview(id: ComposerAttachment.ID) {
    guard let index = composer.attachments.firstIndex(where: { $0.id == id }),
      let window = container.window, let panel = QLPreviewPanel.shared()
    else { return }
    previewAttachments = composer.attachments
    initialPreviewItemIndex = index
    guard window.makeFirstResponder(container) else {
      closePreview()
      return
    }
    panel.updateController()
    panel.makeKeyAndOrderFront(nil)
    if panel.currentController as AnyObject? === self {
      panel.reloadData()
      panel.currentPreviewItemIndex = index
    }
  }

  private func synchronizePreviewAttachments() {
    guard !previewAttachments.isEmpty,
      previewAttachments.map(\.id) != composer.attachments.map(\.id)
    else { return }
    guard let id = previewAttachmentID,
      let index = composer.attachments.firstIndex(where: { $0.id == id })
    else {
      closePreview()
      return
    }
    previewAttachments = composer.attachments
    initialPreviewItemIndex = index
    if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.currentController as AnyObject? === self
    {
      panel.reloadData()
      panel.currentPreviewItemIndex = index
    }
  }

  private func closePreview() {
    if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.currentController as AnyObject? === self
    {
      panel.close()
      if panel.dataSource === self { panel.dataSource = nil }
    }
    previewAttachments = []
    initialPreviewItemIndex = 0
  }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    MainActor.assumeIsolated { !previewAttachments.isEmpty }
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      panel.dataSource = self
      panel.reloadData()
      panel.currentPreviewItemIndex = initialPreviewItemIndex
    }
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      if panel.dataSource === self { panel.dataSource = nil }
      previewAttachments = []
      initialPreviewItemIndex = 0
    }
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewAttachments.count }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    guard previewAttachments.indices.contains(index) else { return nil }
    return previewAttachments[index].sourceURL as NSURL
  }
}
