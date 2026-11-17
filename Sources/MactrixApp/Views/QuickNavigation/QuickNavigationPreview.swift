#if DEBUG
  import AppKit
  import SwiftUI

  private struct QuickNavigationPreview: NSViewRepresentable {
    var query = ""

    func makeNSView(context: Context) -> QuickNavigationView {
      let session = QuickNavigationSession()
      session.updateCandidates([
        .init(
          id: "!general:example.org", displayName: "General", canonicalAlias: "#general:example.org"
        ),
        .init(
          id: "!dev:example.org", displayName: "Development", canonicalAlias: "#dev:example.org"),
        .init(
          id: "!design:example.org", displayName: "Design", canonicalAlias: "#design:example.org"),
        .init(id: "!alice:example.org", displayName: "Alice", canonicalAlias: nil),
        .init(
          id: "!space:example.org", displayName: "Community Space",
          canonicalAlias: "#community:example.org"),
        .init(
          id: "!help:example.org", displayName: "Help & Support",
          canonicalAlias: "#help:example.org"),
        .init(id: "!random:example.org", displayName: "Random", canonicalAlias: nil),
        .init(id: "!cafe:example.org", displayName: "Café ☕️", canonicalAlias: "#cafe:example.org"),
        .init(id: "!announcements:example.org", displayName: "Announcements", canonicalAlias: nil),
        .init(id: "!unnamed:example.org", displayName: nil, canonicalAlias: nil),
      ])
      session.updateQuery(query)
      return QuickNavigationView(session: session)
    }

    func updateNSView(_ nsView: QuickNavigationView, context: Context) {}
  }

  #Preview("Quick Navigation") {
    QuickNavigationPreview()
      .frame(width: 640, height: 497)
      .padding(24)
  }

  #Preview("Quick Navigation — No Results") {
    QuickNavigationPreview(query: "no matching room")
      .frame(width: 640, height: 133)
      .padding(24)
  }
#endif
