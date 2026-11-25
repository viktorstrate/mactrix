import Foundation
import MactrixUI
import MatrixRustSDK

@MainActor final class MessageEditState {
  let id: EventOrTransactionId
  var text: String
  var isSaving = false
  var error: String?
  var mentionCandidateProvider: (() -> [RoomMember])?
  weak var imageLoader: ImageLoader?
  var onChange: (() -> Void)?
  var onSave: (() -> Void)?
  var onCancel: (() -> Void)?

  init(id: EventOrTransactionId, text: String) {
    self.id = id
    self.text = text
  }
}
