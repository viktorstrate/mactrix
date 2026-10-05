import AppKit
import Testing
import UniformTypeIdentifiers

@testable import MactrixApp

@MainActor
struct ComposerAttachmentPreviewTileTests {
  @Test func imageAndVideoUseAvailableThumbnails() {
    #expect(attachment(kind: .image, preview: true).usesThumbnail)
    #expect(attachment(kind: .video, preview: true).usesThumbnail)
  }

  @Test func audioAndFilesUseTypeIconsEvenWhenAnImageIsPresent() {
    #expect(!attachment(kind: .audio, preview: true).usesThumbnail)
    #expect(!attachment(kind: .file, preview: true).usesThumbnail)
    #expect(!attachment(kind: .image, preview: false).usesThumbnail)
  }

  private func attachment(kind: ComposerAttachment.Kind, preview: Bool) -> ComposerAttachment {
    ComposerAttachment(
      sourceURL: URL(fileURLWithPath: "/tmp/attachment"),
      filename: "filename.pdf",
      contentType: .pdf,
      byteCount: 1,
      kind: kind,
      storageOwnership: .externalUserFile,
      deduplicationIdentity: .absolutePath("/tmp/attachment"),
      preview: preview ? NSImage(size: CGSize(width: 1, height: 1)) : nil)
  }
}
