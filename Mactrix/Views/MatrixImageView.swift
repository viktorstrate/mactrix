import MatrixRustSDK
import SwiftUI
import UniformTypeIdentifiers

struct MatrixImageView: View {
    let mediaSource: MediaSource?
    let mimeType: String?

    @Environment(AppState.self) private var appState
    @State private var image: Image? = nil
    @State private var errorMessage: String? = nil

    init(mediaSource: MediaSource?, mimeType: String?) {
        self.mediaSource = mediaSource
        self.mimeType = mimeType
        if let url = mediaSource?.url(),
           let cached = MatrixClient.imageCache.object(forKey: NSString(string: url)) {
            self._image = State(initialValue: Image(nsImage: cached))
        }
    }

    @ViewBuilder
    var content: some View {
        if let image {
            image
        } else if let errorMessage {
            VStack {
                ContentUnavailableView("Error loading image", image: "photo.badge.exclamationmark")
                Text(errorMessage)
            }
        } else if mediaSource == nil {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
        } else {
            ProgressView {
                Text("Fetching image")
            }
        }
    }

    var body: some View {
        content
            .task(id: mediaSource?.url(), priority: .utility) {
                guard image == nil else { return }
                guard let matrixClient = appState.matrixClient else {
                    errorMessage = "Matrix client not available"
                    return
                }

                guard let mediaSource else { return }

                let cacheKey = NSString(string: mediaSource.url())
                if let cached = MatrixClient.imageCache.object(forKey: cacheKey) {
                    image = Image(nsImage: cached)
                    return
                }

                do {
                    let data = try await matrixClient.client.getMediaContent(mediaSource: mediaSource)
                    let contentType = mimeType.flatMap { UTType(mimeType: $0) }
                    image = try await Image(importing: data, contentType: contentType)
                    if let nsImage = NSImage(data: data) {
                        MatrixClient.imageCache.setObject(nsImage, forKey: cacheKey, cost: data.count)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
    }
}
