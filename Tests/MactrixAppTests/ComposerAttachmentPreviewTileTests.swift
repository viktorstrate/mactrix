import AppKit
import Testing
import UniformTypeIdentifiers

@testable import MactrixApp

@MainActor
struct ComposerAttachmentPreviewTileTests {
  @Test func imageAndVideoUseAvailableThumbnails() {
    #expect(
      ComposerAttachmentPreviewTile.usesThumbnail(for: attachment(kind: .image, preview: true)))
    #expect(
      ComposerAttachmentPreviewTile.usesThumbnail(for: attachment(kind: .video, preview: true)))
  }

  @Test func audioAndFilesUseTypeIconsEvenWhenAnImageIsPresent() {
    #expect(
      !ComposerAttachmentPreviewTile.usesThumbnail(for: attachment(kind: .audio, preview: true)))
    #expect(
      !ComposerAttachmentPreviewTile.usesThumbnail(for: attachment(kind: .file, preview: true)))
    #expect(
      !ComposerAttachmentPreviewTile.usesThumbnail(for: attachment(kind: .image, preview: false)))
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
