import ContactLinking
import MactrixUI
import MatrixIntegration
import MatrixRustSDK
import OSLog
import SwiftUI

struct SearchMessageRowView: View {
  @Environment(\.calendar) private var calendar

  let result: SearchServiceResult
  let query: String
  let matrixClient: MatrixClient?

  private var matrixName: String? {
    switch result.message.senderProfile {
    case .ready(let name, _, _, _, _): name
    default: nil
    }
  }

  private var avatarURL: String? {
    switch result.message.senderProfile {
    case .ready(_, _, let avatarURL, _, _): avatarURL
    default: nil
    }
  }

  private var roomTitle: String? {
    let roomID = result.roomId
    let entry = matrixClient?.rooms.first { $0.id == roomID }
    let info = entry?.roomInfo
    let room = entry?.room ?? (try? matrixClient?.client.getRoom(roomId: roomID))
    let roomName =
      info?.displayName ?? room?.displayName() ?? info?.canonicalAlias
      ?? room?.canonicalAlias()
    return ContactDirectory.shared.roomTitle(roomName: roomName, roomInfo: info)
  }

  var body: some View {
    let message = result.message
    let contacts = ContactDirectory.shared
    let senderName = contacts.resolvedName(userID: message.sender, matrixName: matrixName)
    let senderHelp =
      contacts.matrixIdentityHelp(userID: message.sender, matrixName: matrixName)
      ?? message.sender
    let date = message.timestamp.date
    let fullTimestamp = date.formatted(date: .complete, time: .shortened)

    HStack(alignment: .top, spacing: 8) {
      AvatarImage(
        userID: message.sender, kind: .user, displayName: senderName, avatarUrl: avatarURL,
        imageLoader: matrixClient
      )
      .frame(width: 24, height: 24)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(senderName)
            .fontWeight(.medium)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(senderHelp)
          Text(timestampLabel(for: date))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(fullTimestamp)
            .accessibilityLabel(fullTimestamp)
        }

        Text(roomTitle ?? String(localized: "Unknown room"))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(roomTitle ?? result.roomId)

        Text(Self.snippet(for: message.content, query: query))
          .font(.callout)
          .lineLimit(3)
      }
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private func timestampLabel(for date: Date) -> String {
    if calendar.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
      return date.formatted(.dateTime.month(.abbreviated).day())
    }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private static func preview(for content: TimelineItemContent) -> (label: String?, body: String) {
    guard case .msgLike(let item) = content, case .message(let message) = item.kind else {
      return (nil, content.userInterfaceText)
    }

    return switch message.msgType {
    case .image(let image): (String(localized: "Image"), image.caption ?? image.filename)
    case .video(let video): (String(localized: "Video"), video.caption ?? video.filename)
    case .audio(let audio):
      (
        audio.voice == nil ? String(localized: "Audio") : String(localized: "Voice message"),
        audio.caption ?? audio.filename
      )
    case .file(let file): (String(localized: "File"), file.caption ?? file.filename)
    case .gallery(let gallery): (String(localized: "Gallery"), gallery.body)
    default: (nil, message.body)
    }
  }

  private static func snippet(for content: TimelineItemContent, query: String) -> AttributedString {
    let (label, body) = preview(for: content)
    let text = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !text.isEmpty else { return AttributedString(label ?? "") }
    let terms = query.split { $0.isWhitespace || $0 == "\"" }.map(String.init)

    func nextMatch(from start: String.Index) -> Range<String.Index>? {
      terms.compactMap {
        text.range(
          of: $0, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex)
      }.min { lhs, rhs in
        lhs.lowerBound == rhs.lowerBound
          ? lhs.upperBound > rhs.upperBound : lhs.lowerBound < rhs.lowerBound
      }
    }

    var start = text.startIndex
    if let match = nextMatch(from: text.startIndex),
      let contextStart = text.index(match.lowerBound, offsetBy: -32, limitedBy: text.startIndex)
    {
      start = contextStart
      if start > text.startIndex, text[text.index(before: start)] != " ",
        let space = text[start..<match.lowerBound].firstIndex(of: " ")
      {
        start = text.index(after: space)
      }
    }

    var snippet = AttributedString()
    if let label { snippet.append(AttributedString(String(localized: "\(label): "))) }
    if start > text.startIndex { snippet.append(AttributedString("…")) }

    var cursor = start
    while let match = nextMatch(from: cursor), !match.isEmpty {
      snippet.append(AttributedString(text[cursor..<match.lowerBound]))
      var emphasis = AttributedString(text[match])
      emphasis.font = .callout.weight(.semibold)
      snippet.append(emphasis)
      cursor = match.upperBound
    }
    snippet.append(AttributedString(text[cursor...]))
    return snippet
  }
}
