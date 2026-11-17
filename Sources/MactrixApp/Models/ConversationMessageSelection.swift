import MatrixRustSDK

/// Routes scene commands to a selected message in the timeline controller.
@MainActor
struct ConversationMessageSelection {
  weak var owner: TimelineViewController?
  let messageID: String

  private var event: EventTimelineItem? {
    guard let owner,
      case .joinedRoom(let activeTimeline) = owner.windowState.selectedScreen,
      activeTimeline.room.id == owner.timeline.room.id
    else { return nil }
    return owner.selectedMessageEvent(matching: messageID)
  }

  var isPinned: Bool {
    guard let owner, let event else { return false }
    return owner.isMessagePinned(event)
  }

  var downloadFilenames: [String] {
    guard let event else { return [] }
    return MessageDownloadAttachment.attachments(for: event).map(\.suggestedFilename)
  }

  func canPerform(_ action: MessageHoverOverlayView.Action) -> Bool {
    guard let owner, let event, owner.view.window != nil else { return false }
    return owner.canPerformMessageAction(action, for: event)
  }

  func perform(_ action: MessageHoverOverlayView.Action) {
    guard canPerform(action), let owner, let event else { return }
    owner.performMessageAction(action, for: event)
  }
}
