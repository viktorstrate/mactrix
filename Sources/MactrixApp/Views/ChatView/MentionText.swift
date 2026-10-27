import AppKit
import MactrixUI
import Utils

extension NSPasteboard.PasteboardType {
  static let mactrixComposerText = Self("org.mactrix.composer-text")
}

enum MentionClipboardSegment: Codable {
  case text(String)
  case mention(UserDragPayload)

  static func encode(segments: [MentionClipboardSegment]) -> Data? {
    try? JSONEncoder().encode(segments)
  }

  static func decode(data: Data) -> [MentionClipboardSegment]? {
    try? JSONDecoder().decode([MentionClipboardSegment].self, from: data)
  }
}

@MainActor
enum MentionText {
  /// Decorates rendered links, leaving plain user IDs and non-user links untouched.
  static func replacingUserLinks(in text: NSAttributedString, imageLoader: ImageLoader? = nil)
    -> NSAttributedString
  {
    var mentions: [(NSRange, UserDragPayload, URL)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
      guard let url, let userID = userID(for: url) else { return }
      let name = (text.string as NSString).substring(with: range)
      // A single-line pill must not swallow structural breaks in linked HTML content.
      guard name.rangeOfCharacter(from: .newlines) == nil else { return }
      mentions.append((range, UserDragPayload(userID: userID, username: name), url))
    }

    let result = NSMutableAttributedString(attributedString: text)
    for (range, payload, url) in mentions.reversed() {
      var attributes = text.attributes(at: range.location, effectiveRange: nil)
      // Navigation belongs to the host. Pills are intentionally non-interactive for now.
      attributes.removeValue(forKey: .link)
      attributes.removeValue(forKey: .attachment)
      attributes.removeValue(forKey: .underlineStyle)
      let attachment = MentionAttachment(
        payload: payload, imageLoader: imageLoader, navigationURL: url)
      result.replaceCharacters(
        in: range, with: NSAttributedString(attachment: attachment, attributes: attributes))
    }
    return result
  }

  private static func userID(for url: URL) -> String? {
    let userID: String
    if url.scheme == "https", url.host == "matrix.to", url.path == "/" || url.path.isEmpty {
      guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
        fragment.hasPrefix("/@")
      else { return nil }
      userID = String(fragment.dropFirst().prefix { $0 != "?" })
    } else {
      guard let uri = try? MatrixUriScheme(parseUrl: url.absoluteString),
        case .user(let id) = uri.kind
      else { return nil }
      userID = id.removingPercentEncoding ?? id
    }
    guard userID.hasPrefix("@"), let separator = userID.firstIndex(of: ":"),
      separator > userID.index(after: userID.startIndex),
      userID.index(after: separator) < userID.endIndex,
      userID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      !userID[separator...].contains("/"), !userID.contains("?"), !userID.contains("#")
    else { return nil }
    return userID
  }

  static func project(_ text: NSAttributedString, asMarkdown: Bool)
    -> (text: String, mentionedUserIDs: [String])
  {
    var result = ""
    var mentionedUserIDs: [String] = []
    var seenUserIDs: Set<String> = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      attachment, range, _ in
      if let mention = attachment as? MentionAttachment {
        if seenUserIDs.insert(mention.payload.userID).inserted {
          mentionedUserIDs.append(mention.payload.userID)
        }
        result +=
          asMarkdown
          ? (mention.payload.markdownLink ?? mention.payload.userID) : mention.payload.userID
      } else {
        result += (text.string as NSString).substring(with: range)
      }
    }
    return (result, mentionedUserIDs)
  }

  static func containsMentions(_ text: NSAttributedString) -> Bool {
    var found = false
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, _, stop in
      if value is MentionAttachment {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  static func writeSelection(
    _ selected: NSAttributedString, to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType
  ) -> Bool {
    switch type {
    case .string:
      return pasteboard.setString(project(selected, asMarkdown: false).text, forType: .string)
    case .rtf, .html:
      let exported = exportingMentions(in: selected)
      let documentType: NSAttributedString.DocumentType = type == .rtf ? .rtf : .html
      guard
        let data = try? exported.data(
          from: NSRange(location: 0, length: exported.length),
          documentAttributes: [.documentType: documentType])
      else { return false }
      return pasteboard.setData(data, forType: type)
    case .mactrixComposerText:
      var segments: [MentionClipboardSegment] = []
      selected.enumerateAttribute(.attachment, in: NSRange(location: 0, length: selected.length)) {
        attachment, range, _ in
        if let mention = attachment as? MentionAttachment {
          segments.append(.mention(mention.pasteboardPayload))
        } else {
          segments.append(.text((selected.string as NSString).substring(with: range)))
        }
      }
      guard let data = MentionClipboardSegment.encode(segments: segments) else { return false }
      return pasteboard.setData(data, forType: .mactrixComposerText)
    default:
      return false
    }
  }

  private static func exportingMentions(in text: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: text)
    text.enumerateAttribute(
      .attachment, in: NSRange(location: 0, length: text.length), options: .reverse
    ) { value, range, _ in
      guard let mention = value as? MentionAttachment else { return }
      var attributes = text.attributes(at: range.location, effectiveRange: nil)
      attributes.removeValue(forKey: .attachment)
      attributes[.link] = mention.navigationURL
      result.replaceCharacters(
        in: range,
        with: NSAttributedString(string: mention.payload.username, attributes: attributes))
    }
    return result
  }
}

/// Keeps speculative measurements independent of the displayed text view's layout and selection.
@MainActor
enum MentionTextLayout {
  static func height(
    for text: NSAttributedString, width: CGFloat, inset: NSSize = .zero,
    lineFragmentPadding: CGFloat = 0, minimumLineHeight: CGFloat = 0
  ) -> CGFloat {
    let content = NSTextContentStorage()
    let manager = NSTextLayoutManager()
    content.addTextLayoutManager(manager)
    let container = NSTextContainer(
      size: NSSize(width: max(1, width - 2 * inset.width), height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = lineFragmentPadding
    manager.textContainer = container
    content.textStorage?.setAttributedString(text)
    manager.ensureLayout(for: content.documentRange)
    var bottom: CGFloat = 0
    manager.enumerateTextLayoutFragments(
      from: content.documentRange.location, options: [.ensuresLayout, .ensuresExtraLineFragment]
    ) { fragment in
      bottom = max(bottom, fragment.layoutFragmentFrame.maxY)
      return true
    }
    return ceil(max(bottom, minimumLineHeight) + 2 * inset.height)
  }
}
