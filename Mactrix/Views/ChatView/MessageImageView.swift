import MatrixRustSDK
import SwiftUI
import UniformTypeIdentifiers

struct MessageImageView: View {
    let content: ImageMessageContent

    @Environment(AppState.self) private var appState

    @State private var imageData: Data? = nil
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
        .task(id: content.source.url(), priority: .utility) {
            guard let matrixClient = appState.matrixClient else {
                errorMessage = "Matrix client not available"
                return
            }

            do {
                let data = try await matrixClient.client.getMediaContent(mediaSource: content.source)
                imageData = data
                let contentType = content.info?.mimetype.flatMap { UTType(mimeType: $0) }
                image = try await Image(importing: data, contentType: contentType)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
