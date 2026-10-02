import AppKit
import MatrixRustSDK
import QuickLookUI

/// Presents a local file in Quick Look and retains an optional owner for temporary SDK media.
@MainActor final class MediaQuickLookPreview: NSObject, @preconcurrency QLPreviewPanelDataSource {
  static let shared = MediaQuickLookPreview()

  private var retainedFileOwner: AnyObject?
  private var url: URL?

  func show(url: URL, retaining fileOwner: AnyObject? = nil) {
    retainedFileOwner = fileOwner
    self.url = url
    guard let panel = QLPreviewPanel.shared() else { return }
    panel.dataSource = self
    panel.reloadData()
    panel.makeKeyAndOrderFront(nil)
  }

  func show(handle: MediaFileHandle, url: URL) {
    show(url: url, retaining: handle)
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    url as NSURL?
  }
}
