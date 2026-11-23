import Foundation
import Testing

@testable import Utils

struct MatrixUriSchemeTests {
  @Test(arguments: [
    "matrix:roomid/room:example.org/e/event:example.org",
    "matrix:roomid/room%3Aexample.org/e/event%3Aexample.org",
    "matrix:roomid/room:example.org/event/event:example.org",
    "matrix:%72oomid/room:example.org/%65/event:example.org",
    "https://matrix.to/#/!room:example.org/$event:example.org",
    "https://matrix.to/#/%21room%3Aexample.org/%24event%3Aexample.org",
  ])
  func parseRoomEvent(url: String) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomId("!room:example.org"))
    #expect(parsed.event == "$event:example.org")
    #expect(parsed.routingVia.isEmpty)
    #expect(parsed.action == nil)
  }

  @Test(arguments: [
    "matrix:r/room:example.org/e/event",
    "matrix:room/room%3Aexample.org/EVENT/event",
    "https://matrix.to/#/#room:example.org/$event",
    "https://matrix.to/#/%23room%3Aexample.org/%24event",
  ])
  func parseAliasEvent(url: String) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomAlias("#room:example.org"))
    #expect(parsed.event == "$event")
  }

  @Test(arguments: [
    "matrix:roomid/room:example.org/e/event",
    "https://matrix.to/#/!room:example.org/$event",
  ])
  func parseEventQuery(url: String) throws {
    let parsed = try MatrixUriScheme(
      parseUrl: url + "?via=one.example&via=two.example%3A8448&action=%6Aoin&unknown=ignored")

    #expect(parsed.event == "$event")
    #expect(parsed.routingVia == ["one.example", "two.example:8448"])
    #expect(parsed.action == .join)
  }

  @Test(arguments: [
    "matrix:r/room%2Fpart%3Fname%3Aexample.org/e/event%2Fpart%3Fquery%26value%3D1%252F",
    "https://matrix.to/#/%23room%2Fpart%3Fname%3Aexample.org/%24event%2Fpart%3Fquery%26value%3D1%252F",
  ])
  func decodeComponentsOnlyOnce(url: String) throws {
    let parsed = try MatrixUriScheme(
      parseUrl:
        url + "?v%69a=%5B2001%3Adb8%3A%3A1%5D%3A8448&custom=host%26name%3Dvalue%252F&action=chat")

    #expect(parsed.kind == .roomAlias("#room/part?name:example.org"))
    #expect(parsed.event == "$event/part?query&value=1%2F")
    #expect(parsed.routingVia == ["[2001:db8::1]:8448"])
    #expect(parsed.action == nil)
  }

  @Test(arguments: [
    "https://matrix.to/#/!room:example.org/$event?via=one.example&via=two.example&action=join",
    "https://matrix.to/#/#room:example.org/$event?via=one.example&via=two.example&action=join",
    "https://matrix.to/#/@alice:example.org?action=chat",
  ])
  func matrixToInitializersAgree(url: String) throws {
    #expect(
      try MatrixUriScheme(parseMatrixToUrl: url) == MatrixUriScheme(parseUrl: url))
  }

  @Test(arguments: [
    (
      "https://matrix.to/#/@alice:example.org?action=chat",
      MatrixUriScheme.Kind.user("@alice:example.org")
    ),
    ("https://matrix.to/#/%23room%3Aexample.org?action=chat", .roomAlias("#room:example.org")),
    ("https://matrix.to/#/!room:example.org?action=chat", .roomId("!room:example.org")),
    ("matrix:u/alice%3Aexample.org?action=chat", .user("@alice:example.org")),
    ("matrix:r/room%3Aexample.org?action=chat", .roomAlias("#room:example.org")),
    ("matrix:roomid/room%3Aexample.org?action=chat", .roomId("!room:example.org")),
  ])
  func parseLinksWithoutEvents(url: String, kind: MatrixUriScheme.Kind) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == kind)
    #expect(parsed.event == nil)
    if case .user = kind {
      #expect(parsed.action == .chat)
    } else {
      #expect(parsed.action == nil)
    }
  }

  @Test func ignoreUnknownAndEmptyQueryParameters() throws {
    let parsed = try MatrixUriScheme(
      parseUrl:
        "matrix:r/room:example.org?via=&via&com.example.action=chat%26via%3Dignored&action=join&via=host:8448&"
    )

    #expect(parsed.routingVia == ["host:8448"])
    #expect(parsed.action == .join)
  }

  @Test(arguments: [
    "matrix:u/alice:example.org/e/event",
    "matrix:u/alice:example.org/e/$event",
    "matrix:roomid/room:example.org/e/",
    "matrix:roomid/room:example.org/e/?via=example.org",
    "matrix:r/room:example.org/e/",
    "matrix:r/room:example.org/e",
    "matrix:user/alice:example.org/event/event",
    "matrix:r/room:example.org/e/%00",
    "matrix:r/room:example.org/e/event/extra",
    "matrix:roomid/#room:example.org/e/event",
    "matrix:r/%23/e/event",
    "matrix:r/room:example.org/e/%ZZ",
    "matrix:r/room%ZZ:example.org/e/event",
    "matrix:r/room:example.org/e/event?via=%ZZ",
    "https://matrix.to/#/@alice:example.org/$event",
    "https://matrix.to/#/%40alice:example.org/%24event",
    "https://matrix.to/#/!room:example.org/",
    "https://matrix.to/#/#room:example.org/?via=example.org",
    "https://matrix.to/#/!room:example.org/$",
    "https://matrix.to/#/!room:example.org/event",
    "https://matrix.to/#/!room:example.org/$event/extra",
    "https://matrix.to/#/!room:example.org/%24event%ZZ",
    "https://matrix.to/#/!room:example.org/$event?via=%ZZ",
    "https://matrix.to/#/room:example.org/$event",
    "https://matrix.to/#/",
    "https://matrix.to/#/!",
    "https://matrix.to.evil/#/!room:example.org/$event",
  ])
  func rejectInvalidLinks(url: String) {
    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseUrl: url)
    }
    if url.hasPrefix("https://matrix.to/") {
      #expect(throws: MatrixUriError.self) {
        try MatrixUriScheme(parseMatrixToUrl: url)
      }
    }
  }

  @Test(arguments: [
    "matrix://example.org/r/room:example.org",
    "matrix://example.org:8448/r/room:example.org",
    "matrix://user:password@example.org/r/room:example.org",
    "matrix://[2001:db8::1]:8448/r/room:example.org",
    "matrix://[v1.future:host]/room/room:example.org",
    "matrix://[invalid]/r/room:example.org",
    "matrix:///r/room:example.org",
    "MATRIX:r/room:example.org",
    "MaTrIx:r/room:example.org",
    "MaTrIx://example.org/r/room:example.org",
  ])
  func parseAuthoritiesAndCaseInsensitiveScheme(url: String) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomAlias("#room:example.org"))
    #expect(parsed.event == nil)
    #expect(parsed.routingVia.isEmpty)
    #expect(parsed.action == nil)
  }

  @Test(arguments: [
    "matrix:r/room:example.org#ignored/e/event?via=invalid%26host&action=join",
    "matrix:r/room:example.org#",
    "matrix:r/room:example.org?custom=value#&via=invalid%26host&action=join",
  ])
  func ignoreFragmentAfterIdentifierOrQuery(url: String) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomAlias("#room:example.org"))
    #expect(parsed.event == nil)
    #expect(parsed.routingVia.isEmpty)
    #expect(parsed.action == nil)
  }

  @Test(arguments: [
    "matrix:r/room:example.org/e/event#ignored?via=invalid%26host&action=chat",
    "matrix:r/room:example.org/e/event?via=example.org&action=join#&via=invalid%26host",
  ])
  func ignoreFragmentAfterEvent(url: String) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomAlias("#room:example.org"))
    #expect(parsed.event == "$event")
    if url.contains("?via=example.org") {
      #expect(parsed.routingVia == ["example.org"])
      #expect(parsed.action == .join)
    } else {
      #expect(parsed.routingVia.isEmpty)
      #expect(parsed.action == nil)
    }
  }

  @Test(arguments: [
    ("matrix:u/alice:example.org?action=join", Optional<MatrixUriScheme.Action>.none),
    ("matrix:u/alice:example.org?action=chat", .chat),
    ("matrix:r/room:example.org?action=chat", nil),
    ("matrix:r/room:example.org?action=join", .join),
    ("matrix:roomid/opaque?action=chat", nil),
    ("matrix:roomid/opaque?action=join", .join),
    ("matrix:r/room:example.org/e/event?action=chat", nil),
    ("matrix:r/room:example.org/e/event?action=join", .join),
    ("matrix:roomid/opaque/e/event?action=chat", nil),
    ("matrix:roomid/opaque/e/event?action=join", .join),
    ("https://matrix.to/#/@alice:example.org?action=join", nil),
    ("https://matrix.to/#/@alice:example.org?action=chat", .chat),
    ("https://matrix.to/#/#room:example.org?action=chat", nil),
    ("https://matrix.to/#/#room:example.org?action=join", .join),
    ("https://matrix.to/#/!opaque?action=chat", nil),
    ("https://matrix.to/#/!opaque?action=join", .join),
    ("https://matrix.to/#/!opaque/$event?action=chat", nil),
    ("https://matrix.to/#/!opaque/$event?action=join", .join),
    ("https://matrix.to/#/#room:example.org/$event?action=chat", nil),
    ("https://matrix.to/#/#room:example.org/$event?action=join", .join),
    ("matrix:r/room:example.org?ACTION=JOIN", .join),
    ("matrix:u/alice:example.org?action=unknown", nil),
    ("matrix:r/room:example.org?action=unknown&action=join", .join),
    ("matrix:r/room:example.org?action=join&action=unknown", nil),
    ("matrix:r/room:example.org?action=join&action=chat", nil),
    ("matrix:r/room:example.org?action=join&action=", nil),
  ])
  func actionsDependOnIdentifierKind(url: String, action: MatrixUriScheme.Action?) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.action == action)
    if url.hasPrefix("https://matrix.to/") {
      #expect(try MatrixUriScheme(parseMatrixToUrl: url).action == action)
    }
  }

  @Test(arguments: [
    "matrix:roomid/opaque",
    "https://matrix.to/#/!opaque",
  ])
  func preserveRoutingServerOrderAndDuplicates(url: String) throws {
    let parsed = try MatrixUriScheme(
      parseUrl:
        url
        + "?via=example.org&via=&via&via=192.0.2.1%3A8448&via=%5B2001%3Adb8%3A%3A1%5D&via=example.org"
    )

    #expect(parsed.routingVia == ["example.org", "192.0.2.1:8448", "[2001:db8::1]", "example.org"])
  }

  @Test(arguments: [
    (
      "matrix:r/room+name:example.org/e/event+name",
      MatrixUriScheme.Kind.roomAlias("#room+name:example.org")
    ),
    (
      "https://matrix.to/#/%23room+name:example.org/$event+name",
      .roomAlias("#room+name:example.org")
    ),
  ])
  func plusIsNotFormEncodedSpace(url: String, kind: MatrixUriScheme.Kind) throws {
    let parsed = try MatrixUriScheme(parseUrl: url + "?action=join+&custom=a+b")

    #expect(parsed.kind == kind)
    #expect(parsed.event == "$event+name")
    #expect(parsed.action == nil)
  }

  @Test(arguments: [
    ("matrix:u/alice:example.org", MatrixUriScheme.Kind.user("@alice:example.org")),
    ("matrix:u/alice:example.org?action=chat", .user("@alice:example.org")),
    ("matrix:r/somewhere:example.org", .roomAlias("#somewhere:example.org")),
    ("matrix:r/somewhere:example.org?action=join", .roomAlias("#somewhere:example.org")),
    ("matrix:roomid/somewhere:example.org", .roomId("!somewhere:example.org")),
    ("matrix:roomid/somewhere:example.org?via=elsewhere.ca", .roomId("!somewhere:example.org")),
    ("matrix:roomid/opaque", .roomId("!opaque")),
    ("matrix:USER/Alice:EXAMPLE.org", .user("@Alice:EXAMPLE.org")),
    ("matrix:u/%40alice%3Aexample.org", .user("@@alice:example.org")),
    ("matrix:u/!alice%3Aexample.org", .user("@!alice:example.org")),
    ("matrix:u/%CC%81:example.org", .user("@\u{301}:example.org")),
    ("matrix:r/%23room%3Aexample.org", .roomAlias("##room:example.org")),
    ("matrix:r/@room:example.org", .roomAlias("#@room:example.org")),
    ("matrix:roomid/%21room", .roomId("!!room")),
    ("https://matrix.to/#/@@alice:example.org", .user("@@alice:example.org")),
    ("https://matrix.to/#/@%CC%81:example.org", .user("@\u{301}:example.org")),
    ("https://matrix.to/#/%23%23room:example.org", .roomAlias("##room:example.org")),
    ("matrix:u/%C3%85lice:example.org", .user("@Ålice:example.org")),
    ("matrix:u/:example.org", .user("@:example.org")),
    ("matrix:r/:example.org", .roomAlias("#:example.org")),
    ("matrix:r/%E6%97%A5%E6%9C%AC%E8%AA%9E:example.org", .roomAlias("#日本語:example.org")),
    ("https://matrix.to/#/@Alice:example.org", .user("@Alice:example.org")),
    ("https://matrix.to/#/%40%C3%85lice:example.org", .user("@Ålice:example.org")),
    ("https://matrix.to/#/@:example.org", .user("@:example.org")),
    ("https://matrix.to/#/%23:example.org", .roomAlias("#:example.org")),
    (
      "https://matrix.to/#/%23%E6%97%A5%E6%9C%AC%E8%AA%9E:example.org",
      .roomAlias("#日本語:example.org")
    ),
  ])
  func specAndHistoricalIdentifierCompatibility(url: String, kind: MatrixUriScheme.Kind) throws {
    let parsed = try MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == kind)
    #expect(parsed.event == nil)
  }

  @Test(arguments: [
    "example.org", "localhost", "example.org:8448", "example.org:99999",
    "192.0.2.1", "192.0.2.1:8448", "[::1]", "[2001:db8::1]:8448", "[::ffff:192.0.2.1]",
    "host+name", "256.0.2.1", "[invalid]", "example.org:", "example.org:123456",
  ])
  func acceptServerAuthoritiesWithoutValidatingAddresses(server: String) throws {
    let encoded = server.replacingOccurrences(of: "[", with: "%5B")
      .replacingOccurrences(of: "]", with: "%5D")
    for scheme in ["matrix:", "https://matrix.to/#/"] {
      let isMatrix = scheme == "matrix:"
      let user = try MatrixUriScheme(
        parseUrl: scheme + (isMatrix ? "u/" : "@") + "alice:" + encoded)
      let alias = try MatrixUriScheme(
        parseUrl: scheme + (isMatrix ? "r/" : "%23") + "room:" + encoded)
      let routing = try MatrixUriScheme(
        parseUrl: scheme + (isMatrix ? "roomid/" : "!") + "opaque?via=" + encoded)

      #expect(user.kind == .user("@alice:" + server))
      #expect(alias.kind == .roomAlias("#room:" + server))
      #expect(routing.routingVia == [server])
    }
  }

  @Test(arguments: [
    "matrix:", "matrix:u", "matrix:u/", "matrix:r/", "matrix:roomid/",
    "matrix:/r/room:example.org", "matrix://r/room:example.org",
    "matrix://example.orgr/room:example.org", "matrix:////r/room:example.org",
    "matrix:r//room:example.org", "matrix:r/room:example.org/",
    "matrix:r/room:example.org//e/event", "matrix:r/room:example.org/e//event",
    "matrix:r/room:example.org/room/event", "matrix:r/room:example.org/%2565/event",
    "matrix:r/room:example.org/e/event/", "matrix:r/room:example.org/e/event/e/another",
    "matrix:r/#room:example.org", "matrix:r/#room:example.org/e/event",
    "matrix:unknown/room:example.org", "matrix:event/event", "matrix:e/event",
    "matrix://[invalid/r/room:example.org", "other:r/room:example.org",
    "https://matrix.to/#//%23room:example.org", "https://matrix.to/#/#room:example.org//",
  ])
  func rejectInvalidPathSequences(url: String) {
    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseUrl: url)
    }
  }

  @Test(arguments: ["%", "%2", "%GG", "%FF", "%C3%28", "%C0%AF", "%ED%A0%80"])
  func rejectMalformedEncodingAndInvalidUTF8(encoded: String) {
    let urls = [
      "matrix:r/room" + encoded + ":example.org",
      "matrix:r/room:example.org/e/event" + encoded,
      "matrix:r/room:example.org?via=" + encoded,
      "matrix:r/room:example.org?custom=" + encoded,
      "https://matrix.to/#/%23room" + encoded + ":example.org",
      "https://matrix.to/#/!opaque/$event" + encoded,
      "https://matrix.to/#/!opaque?via=" + encoded,
    ]
    for url in urls {
      #expect(throws: MatrixUriError.self) {
        try MatrixUriScheme(parseUrl: url)
      }
    }
  }

  @Test(arguments: [
    "https://matrix.to.evil/#/@alice:example.org",
    "https://matrix.to@evil.example/#/@alice:example.org",
    "https://evil.example/matrix.to/#/@alice:example.org",
    "https://matrix.to.evil/?url=https://matrix.to/#/@alice:example.org",
    "http://matrix.to/#/@alice:example.org",
    "https://matrix.to/#@alice:example.org",
    "https://matrix.to/@alice:example.org",
  ])
  func rejectUnsafeMatrixToUrls(url: String) {
    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseUrl: url)
    }
    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseMatrixToUrl: url)
    }
  }

  @Test(arguments: [
    "matrix:u/alice", "matrix:r/room", "matrix:u/alice:", "matrix:r/room:",
    "matrix:u/alice:[::1]", "matrix:roomid/opaque?via=[::1]",
    "matrix:u/alice:%CC%81example.org",
    "matrix:u/alice%00:example.org", "matrix:r/room%00:example.org",
    "matrix:roomid/room%00", "matrix:roomid/room/e/event%00",
    "https://matrix.to/#/@alice", "https://matrix.to/#/%23room",
    "https://matrix.to/#/@alice:", "https://matrix.to/#/%23room:",
    "https://matrix.to/#/@alice%00:example.org", "https://matrix.to/#/!room%00",
  ])
  func rejectInvalidIdentifiers(url: String) {
    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseUrl: url)
    }
  }

  @Test(arguments: [
    "bad%20host", "example.org:abc", "example.org:-1", "example.org:%D9%A1",
    "%3A8448", "2001:db8::1", "%5B2001:db8::1", "%5B::1%5D:abc", "%5B::1%00%5D",
    "example.org%2Fpath", "example.org%3Fquery", "example.org%23fragment",
    "example.org%3F", "example.org%23", "user%40example.org", "user:pass%40example.org",
    "%40example.org", "example.org%00",
  ])
  func rejectMalformedServerAuthorities(server: String) {
    let urls = [
      "matrix:u/alice:" + server,
      "matrix:r/room:" + server,
      "matrix:roomid/opaque?via=" + server,
      "https://matrix.to/#/@alice:" + server,
      "https://matrix.to/#/%23room:" + server,
      "https://matrix.to/#/!opaque?via=" + server,
    ]
    for url in urls {
      #expect(throws: MatrixUriError.self) {
        try MatrixUriScheme(parseUrl: url)
      }
    }
  }

  @Test(arguments: ["u/", "r/"])
  func identifierLengthLimitUsesNormalizedUTF8Bytes(type: String) throws {
    // The sigil and ":example.org" use 13 bytes, leaving 242 for the localpart.
    let asciiBoundary = String(repeating: "a", count: 242)
    let unicodeBoundary = String(repeating: "%C3%A9", count: 121)
    for localpart in [asciiBoundary, unicodeBoundary] {
      let url = "matrix:" + type + localpart + ":example.org"
      let parsed = try MatrixUriScheme(parseUrl: url)
      switch parsed.kind {
      case .user(let id), .roomAlias(let id):
        #expect(id.utf8.count == 255)
      case .roomId:
        Issue.record("Expected a user or room alias")
      }
      #expect(throws: MatrixUriError.self) {
        try MatrixUriScheme(parseUrl: "matrix:" + type + localpart + "a:example.org")
      }
    }
  }

  @Test func preserveLeadingSigilInEventBody() throws {
    let matrix = try MatrixUriScheme(parseUrl: "matrix:roomid/room/e/%24event")
    let matrixTo = try MatrixUriScheme(parseUrl: "https://matrix.to/#/!room/$$event")

    #expect(matrix.event == "$$event")
    #expect(matrix == matrixTo)
  }

  @Test(arguments: [
    ("matrix:roomid/", "/e/"),
    ("https://matrix.to/#/!", "/$"),
  ])
  func opaqueIdentifierLengthLimit(roomPrefix: String, eventSeparator: String) throws {
    let body = String(repeating: "a", count: 254)
    let parsed = try MatrixUriScheme(parseUrl: roomPrefix + body + eventSeparator + body)
    #expect(parsed.kind == .roomId("!" + body))
    #expect(parsed.event == "$" + body)

    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseUrl: roomPrefix + body + "a")
    }
    #expect(throws: MatrixUriError.self) {
      try MatrixUriScheme(parseUrl: roomPrefix + body + eventSeparator + body + "a")
    }
  }

  @Test func routeUserWithoutAction() throws {
    let parsed = try MatrixUriScheme(parseUrl: "matrix:u/alice:example.org?via=Elsewhere.ca")

    #expect(parsed.kind == .user("@alice:example.org"))
    #expect(parsed.routingVia == ["Elsewhere.ca"])
    #expect(parsed.action == nil)
  }

  @Test func parseSimpleRoomAlias() throws {
    let url = "matrix:r/somewhere:example.org"

    let parsed = try Utils.MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomAlias("#somewhere:example.org"))
  }

  @Test func parseSimpleRoomId() throws {
    let url = "matrix:roomid/somewhere:example.org?via=elsewhere.ca"

    let parsed = try Utils.MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .roomId("!somewhere:example.org"))
    #expect(parsed.routingVia == ["elsewhere.ca"])
  }

  @Test func parseUserChat() throws {
    let url = "matrix:u/alice:example.org?action=chat"

    let parsed = try Utils.MatrixUriScheme(parseUrl: url)

    #expect(parsed.kind == .user("@alice:example.org"))
    #expect(parsed.action == .chat)
  }
}
