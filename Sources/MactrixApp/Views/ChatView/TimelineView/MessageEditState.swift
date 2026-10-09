import Foundation
import MatrixRustSDK

@MainActor final class MessageEditState {
  let id: EventOrTransactionId
  var text: String
  var selectedRange: NSRange
  var isSaving = false
  var error: String?
  var onChange: (() -> Void)?
  var onSave: (() -> Void)?
  var onCancel: (() -> Void)?

  init(id: EventOrTransactionId, text: String) {
    self.id = id
    self.text = text
    selectedRange = NSRange(location: (text as NSString).length, length: 0)
  }
}
