import AppKit
import Testing

@testable import MactrixApp

@MainActor
struct ComposerMentionTextViewTests {
  private final class InputTrackingTextView: SubmitableTextView {
    var isComposing = false
    var interpretedEventCount = 0

    override func hasMarkedText() -> Bool { isComposing }

    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
      interpretedEventCount += eventArray.count
    }
  }

  @Test func returnDefersToInputMethodWhileComposing() throws {
    let editor = InputTrackingTextView()
    var submissions = 0
    editor.onSubmit = { submissions += 1 }
    let event = try returnEvent()

    editor.isComposing = true
    editor.keyDown(with: event)
    #expect(submissions == 0)
    #expect(editor.interpretedEventCount == 1)

    editor.isComposing = false
    editor.keyDown(with: event)
    #expect(submissions == 1)
  }

  @Test func commandReturnDoesNotSubmitWhileComposing() throws {
    let editor = InputTrackingTextView()
    var submissions = 0
    editor.onSubmit = { submissions += 1 }
    let event = try returnEvent(modifiers: .command)

    editor.isComposing = true
    _ = editor.performKeyEquivalent(with: event)
    #expect(submissions == 0)

    editor.isComposing = false
    #expect(editor.performKeyEquivalent(with: event))
    #expect(submissions == 1)
  }

  @Test func typedAndPastedTextUpdateTheQuery() {
    let editor = editor()

    editor.insertText("@", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query?.text == "")
    #expect(editor.mentionAutocomplete.query?.range == NSRange(location: 0, length: 1))

    editor.insertText("Ali", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query?.text == "Ali")

    editor.insertText(" ", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query == nil)

    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("@Bob", forType: .string)
    #expect(editor.readSelection(from: pasteboard, type: .string))
    #expect(editor.mentionAutocomplete.query?.text == "Bob")
    #expect(editor.mentionAutocomplete.query?.range == NSRange(location: 5, length: 4))
  }

  @Test func selectionChangesUpdateAndCloseTheQueryWithoutAControllerDelegate() {
    let editor = editor("Hi @Alice later")

    editor.setSelectedRange(NSRange(location: 6, length: 0))
    #expect(editor.mentionAutocomplete.query?.text == "Alice")
    #expect(editor.validatedMentionReplacementRange() == NSRange(location: 3, length: 6))

    editor.setSelectedRange(NSRange(location: 4, length: 2))
    #expect(editor.mentionAutocomplete.query == nil)

    editor.setSelectedRange(NSRange(location: 9, length: 0))
    #expect(editor.mentionAutocomplete.query?.text == "Alice")

    editor.setSelectedRange(NSRange(location: 3, length: 0))
    #expect(editor.mentionAutocomplete.query == nil)

    editor.setSelectedRange(NSRange(location: 14, length: 0))
    #expect(editor.mentionAutocomplete.query == nil)
  }

  @Test func deletingQueryTextAndTriggerUpdatesTheSession() {
    let editor = editor()
    editor.insertText("@A", replacementRange: editor.selectedRange())

    editor.deleteBackward(nil)
    #expect(editor.string == "@")
    #expect(editor.mentionAutocomplete.query?.text == "")

    editor.deleteBackward(nil)
    #expect(editor.string.isEmpty)
    #expect(editor.mentionAutocomplete.query == nil)
    #expect(editor.validatedMentionReplacementRange() == nil)
  }

  @Test func explicitTextChangeNotificationUpdatesAfterStorageEdits() {
    let editor = editor()
    editor.insertText("@Alice", replacementRange: editor.selectedRange())
    editor.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 1), with: "x")

    editor.didChangeText()

    #expect(editor.mentionAutocomplete.query == nil)
  }

  @Test func dismissedTokenStaysSuppressedWhileTyping() {
    let editor = editor()
    editor.insertText("@A", replacementRange: editor.selectedRange())
    editor.mentionAutocomplete.dismiss()

    editor.insertText("lice", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query == nil)
    #expect(editor.mentionAutocomplete.dismissedTriggerLocation == 0)

    editor.insertText(" @Bob", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query?.text == "Bob")
    #expect(editor.mentionAutocomplete.dismissedTriggerLocation == nil)
  }

  @Test func markedTextSuspendsAutocompleteUntilCommitted() {
    let editor = editor()
    editor.insertText("@", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query != nil)

    editor.setMarkedText(
      "あ", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: editor.selectedRange())
    #expect(editor.hasMarkedText())
    #expect(editor.mentionAutocomplete.query == nil)
    #expect(editor.validatedMentionReplacementRange() == nil)

    editor.insertText("あ", replacementRange: editor.markedRange())
    #expect(!editor.hasMarkedText())
    #expect(editor.mentionAutocomplete.query?.text == "あ")
  }

  @Test func unmarkingTextRefreshesCommittedQuery() {
    let editor = editor()
    editor.setMarkedText(
      "@Alice", selectedRange: NSRange(location: 6, length: 0),
      replacementRange: editor.selectedRange())
    #expect(editor.hasMarkedText())
    #expect(editor.mentionAutocomplete.query == nil)

    editor.unmarkText()

    #expect(!editor.hasMarkedText())
    #expect(editor.mentionAutocomplete.query?.text == "Alice")
  }

  @Test func loadingDraftDoesNotStartAutocomplete() {
    let editor = editor()
    editor.insertText("@Bob", replacementRange: editor.selectedRange())
    #expect(editor.mentionAutocomplete.query != nil)

    editor.setMarkdown("@Alice")

    #expect(editor.mentionAutocomplete.query == nil)
    #expect(editor.mentionAutocomplete.dismissedTriggerLocation == nil)
    #expect(editor.markdown == "@Alice")
  }

  @Test func replacementValidationRechecksCurrentStorage() throws {
    let editor = editor()
    editor.insertText("@Alice", replacementRange: editor.selectedRange())
    let originalQuery = try #require(editor.mentionAutocomplete.query)
    #expect(editor.validatedMentionReplacementRange() == originalQuery.range)

    editor.textStorage?.replaceCharacters(in: NSRange(location: 3, length: 1), with: "x")
    #expect(editor.string == "@Alxce")
    // Simulate an acceptance callback still holding the query from before the edit.
    editor.mentionAutocomplete.update(query: originalQuery, suggestions: [])

    #expect(editor.validatedMentionReplacementRange() == nil)
  }

  @Test func popupStaysAlignedAndFullSizedBeyondScreenEdges() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let anchor = NSRect(
      x: screen.visibleFrame.maxX - 20, y: screen.visibleFrame.maxY - 20,
      width: 10, height: 16)
    let size = NSSize(width: 320, height: 264)
    let frame = ComposerMentionAutocompleteWindow.frame(anchoredTo: anchor, preferredSize: size)
    let popup = ComposerMentionAutocompleteWindow()
    defer { popup.close() }

    popup.setFrame(frame, display: false)

    #expect(popup.frame == NSRect(x: anchor.minX, y: anchor.maxY + 4, width: 320, height: 264))
    #expect(popup.frame.maxX > screen.visibleFrame.maxX)
    #expect(popup.frame.maxY > screen.visibleFrame.maxY)
    #expect(
      ComposerMentionAutocompleteWindow.frame(
        anchoredTo: anchor.offsetBy(dx: 40, dy: 30), preferredSize: size)
        == frame.offsetBy(dx: 40, dy: 30))
  }

  @Test func editorsKeepTheirQueriesIndependent() {
    let first = editor()
    let second = editor()

    first.insertText("@Alice", replacementRange: first.selectedRange())

    #expect(first.mentionAutocomplete.query?.text == "Alice")
    #expect(second.mentionAutocomplete.query == nil)
  }

  private func returnEvent(modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
        isARepeat: false, keyCode: 36))
  }

  private func editor(_ markdown: String = "") -> ComposerMentionTextView {
    let editor = ComposerMentionTextView()
    editor.isEditable = true
    editor.font = .systemFont(ofSize: 13)
    editor.setMarkdown(markdown)
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    return editor
  }
}
