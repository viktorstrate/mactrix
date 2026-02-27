import MatrixRustSDK
import Models
import OSLog
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct MessageImageView: View {
    let content: ImageMessageContent

    @Environment(AppState.self) private var appState

    @State private var imageData: Data? = nil
    @State private var image: Image? = nil
    @State private var errorMessage: String? = nil

    var aspectRatio: CGFloat? {
        guard let info = content.info,
              let height = info.height,
              let width = info.width else { return nil }

        return CGFloat(width) / CGFloat(height)
    }

    var maxHeight: CGFloat {
        guard let height = content.info?.height else { return 300 }
        return min(CGFloat(height), 300)
    }

    var contentType: UTType? {
        return content.info?.mimetype.flatMap { UTType(mimeType: $0) }
    }

    @ViewBuilder
    func imageView(image: Image) -> some View {
        Button(
            action: {
                Task { await previewImage() }
            },
            label: {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        let itemProvider = NSItemProvider()
                        itemProvider.suggestedName = content.filename
                        let data = imageData
                        itemProvider.registerDataRepresentation(for: UTType.image, visibility: .all) { completion in
                            completion(data, nil)
                            return nil
                        }
                        return itemProvider
                    }
            }
        )
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.red)
            } else {
                if let image {
                    imageView(image: image)
                } else {
                    ProgressView {
                        Text("Fetching image")
                    }
                }
                if let caption = content.caption {
                    Text(caption.formatAsMarkdown)
                        .textSelection(.enabled)
                }
            }
        }
        .quickLookPreview($quickLookUrl)
        .frame(maxHeight: maxHeight)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .task(id: content.source.url(), priority: .utility) {
            guard let matrixClient = appState.matrixClient else {
                errorMessage = "Matrix client not available"
                return
            }

            do {
                let data = try await matrixClient.client.getMediaContent(mediaSource: content.source)
                imageData = data
                image = try await Image(importing: data, contentType: contentType)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @State private var fileHandle: MediaFileHandle?
    @State private var fileUrl: URL?
    @State private var quickLookUrl: URL?

    func previewImage() async {
        if let fileUrl {
            quickLookUrl = fileUrl
            return
        }

        guard let matrixClient = appState.matrixClient?.client else { return }

        do {
            let handle = try await matrixClient.getMediaFile(
                mediaSource: content.source,
                filename: content.filename,
                mimeType: content.info?.mimetype ?? "",
                useCache: true,
                tempDir: NSTemporaryDirectory()
            )
            fileHandle = handle

            let path = try handle.path()

            let fileUrl = URL(filePath: path, directoryHint: .notDirectory)
            self.fileUrl = fileUrl
            quickLookUrl = fileUrl

            Logger.viewCycle.debug("downloaded image file \(fileUrl.absoluteString)")
        } catch {
            Logger.viewCycle.error("failed to download image file: \(error)")
        }
    }
}
