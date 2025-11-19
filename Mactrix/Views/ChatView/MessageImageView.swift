import MatrixRustSDK
import SwiftUI

struct MessageImageView: View {
    let content: ImageMessageContent

    @Environment(AppState.self) private var appState

    @State private var image: Image? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.red)
            } else {
                if let image = image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                } else {
                    ProgressView {
                        Text("Fetching image")
                    }
                }
                if let caption = content.caption {
                    Text(caption)
                        .font(.caption)
                }
            }
        }
        .task(id: content.source.url()) {
            let url: String = content.source.url()
            guard let matrixClient = appState.matrixClient else {
                errorMessage = "Matrix client not available"
                return
            }

            do {
                let data = try await matrixClient.client.getMediaContent(mediaSource: .fromUrl(url: url))
                image = try await Image(importing: data, contentType: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
