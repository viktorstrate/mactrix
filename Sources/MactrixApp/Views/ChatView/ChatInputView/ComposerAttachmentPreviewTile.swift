import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

extension ComposerAttachment {
  var usesThumbnail: Bool {
    self.preview != nil && (self.kind == .image || self.kind == .video)
  }
}

struct ComposerAttachmentPreviewTile: View {
  static let sideLength: CGFloat = 72

  enum Visual {
    case thumbnail(NSImage)
    case fileIcon(NSImage)
  }

  let attachment: ComposerAttachment
  let onRemove: () -> Void
  @State private var previewURL: URL?

  func visual() -> Visual {
    if attachment.usesThumbnail, let preview = attachment.preview {
      return .thumbnail(preview)
    }
    return .fileIcon(NSWorkspace.shared.icon(for: attachment.contentType))
  }

  private var typeDescription: String {
    switch attachment.kind {
    case .image: "image"
    case .video: "video"
    case .audio: "audio"
    case .file: "file"
    }
  }

  private var tooltip: String {
    if let byteCount = attachment.byteCount {
      return "\(attachment.filename) (\(byteCount.formatted(.byteCount(style: .file))))"
    } else {
      return attachment.filename
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topTrailing) {
        Button {
          previewURL = attachment.sourceURL
        } label: {
          ZStack {
            switch visual() {
            case .thumbnail(let image):
              Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.sideLength, height: Self.sideLength)
            case .fileIcon(let image):
              Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: Self.sideLength, height: Self.sideLength)
            }

            if attachment.kind == .video {
              Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.white, .black.opacity(0.45))
                .accessibilityHidden(true)
            }
          }
          .frame(width: Self.sideLength, height: Self.sideLength)
          // .background(Color(nsColor: .controlBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel("\(attachment.filename), \(typeDescription), \(tooltip)")
        .accessibilityHint("Open in Quick Look")

        Button(action: onRemove) {
          Image(systemName: "xmark")
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .frame(width: 20, height: 20)
            .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(3)
        .help("Remove \(attachment.filename)")
      }
      .frame(width: Self.sideLength, height: Self.sideLength)

      Text(attachment.filename)
        .font(.caption2)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 5)
        .padding(.top, 4)
        .frame(width: Self.sideLength)
    }
    .quickLookPreview($previewURL)
  }
}

struct ComposerAttachmentPreviewStrip: View {
  let attachments: [ComposerAttachment]
  let onRemove: (ComposerAttachment.ID) -> Void

  var body: some View {
    if !attachments.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(attachments) { attachment in
            ComposerAttachmentPreviewTile(attachment: attachment) {
              onRemove(attachment.id)
            }
          }
        }
        .padding(.horizontal, 10)
      }
      .scrollIndicators(.hidden)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Attachments")
    }
  }
}

#if DEBUG
  private enum ComposerAttachmentPreviewFixtures {
    static let thumbnail = NSImage(size: CGSize(width: 320, height: 180), flipped: false) { rect in
      NSColor.systemIndigo.setFill()
      rect.fill()
      NSColor.white.withAlphaComponent(0.2).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 45, dy: 20)).fill()
      return true
    }

    static let attachments: [ComposerAttachment] = [
      attachment(
        filename: "sunset-over-the-mountains.png", type: .png, kind: .image, preview: thumbnail),
      attachment(
        filename: "conference-recording.mov", type: .quickTimeMovie, kind: .video,
        preview: thumbnail),
      attachment(filename: "weekly-standup.m4a", type: .mpeg4Audio, kind: .audio),
      attachment(
        filename: "very-long-project-specification-for-accessibility-testing.pdf", type: .pdf,
        kind: .file),
    ]

    private static func attachment(
      filename: String,
      type: UTType,
      kind: ComposerAttachment.Kind,
      preview: NSImage? = nil
    ) -> ComposerAttachment {
      ComposerAttachment(
        sourceURL: URL(fileURLWithPath: "/tmp/\(filename)"),
        filename: filename,
        contentType: type,
        byteCount: 1_536_000,
        kind: kind,
        storageOwnership: .externalUserFile,
        deduplicationIdentity: .absolutePath("/tmp/\(filename)"),
        preview: preview)
    }
  }

  #Preview("Attachment preview tiles") {
    ComposerAttachmentPreviewStrip(attachments: ComposerAttachmentPreviewFixtures.attachments) {
      _ in
    }
    .padding()
    .frame(width: 440)
  }
#endif
