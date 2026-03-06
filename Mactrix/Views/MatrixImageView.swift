import MatrixRustSDK
import SwiftUI
import UniformTypeIdentifiers

struct MatrixImageView: View {
    let mediaSource: MediaSource?
    let mimeType: String?

    @Environment(AppState.self) private var appState
    @State private var image: Image? = nil
    @State private var errorMessage: String? = nil

    @ViewBuilder
    var content: some View {
        if let image {
            image
        } else if let errorMessage {
            VStack {
                ContentUnavailableView("Error loading image", image: "photo.badge.exclamationmark")
                Text(errorMessage)
            }
        } else {
            ProgressView {
                Text("Fetching image")
            }
        }
    }

    var body: some View {
        content
            .task(id: mediaSource?.url(), priority: .utility) {
                guard let matrixClient = appState.matrixClient else {
                    errorMessage = "Matrix client not available"
                    return
                }

                guard let mediaSource else {
                    return
                }

                do {
                    let data = try await matrixClient.client.getMediaContent(mediaSource: mediaSource)
                    let contentType = mimeType.flatMap { UTType(mimeType: $0) }
                    image = try await Image(importing: data, contentType: contentType)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
    }
}
