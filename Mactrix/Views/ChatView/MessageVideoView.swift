import AVKit
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

struct MessageVideoView: View {
    @Environment(AppState.self) private var appState
    let content: VideoMessageContent

    @State private var fileHandle: MediaFileHandle?
    @State private var video: AVPlayer?

    var aspectRatio: CGFloat? {
        guard let info = content.info,
              let height = info.height, height > 0,
              let width = info.width, width > 0 else { return nil }

        return CGFloat(width) / CGFloat(height)
    }

    var maxHeight: CGFloat {
        guard let height = content.info?.height, height > 0 else { return 300 }
        return min(CGFloat(height), 300)
    }

    func loadVideo() async {
        guard let client = appState.matrixClient?.client else { return }

        do {
            let handle = try await client.getMediaFile(
                mediaSource: content.source,
                filename: content.filename,
                mimeType: content.info?.mimetype ?? "",
                useCache: true,
                tempDir: NSTemporaryDirectory()
            )

            fileHandle = handle
            let path = try handle.path()
            let url = URL(filePath: path, directoryHint: .notDirectory)

            video = AVPlayer(url: url)
            video?.play()
        } catch {
            Logger.viewCycle.error("Failed to load video: \(error)")
        }
    }

    var body: some View {
        VStack {
            if let video {
                TimelineVideoPlayer(videoPlayer: video)
                    .cornerRadius(6)
            } else {
                Button(action: { Task { await loadVideo() } }) {
                    MatrixImageView(mediaSource: content.info?.thumbnailSource, mimeType: content.info?.thumbnailInfo?.mimetype)
                        .overlay {
                            Image(systemName: "play.fill")
                                .resizable()
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                                .frame(width: 48, height: 48)
                                .opacity(0.9)
                        }
                }
                .buttonStyle(.plain)
            }
            if let caption = content.caption, !caption.isEmpty {
                Text(caption.formatAsMarkdown)
                    .textSelection(.enabled)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: maxHeight)
        .frame(minHeight: content.info?.thumbnailSource == nil ? maxHeight : nil)
    }
}
