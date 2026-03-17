import AVKit
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

struct MessageVideoView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("generateVideoThumbnails") var generateVideoThumbnails: Bool = false
    let content: VideoMessageContent

    @State private var fileHandle: MediaFileHandle?
    @State private var video: AVPlayer?
    @State private var generatedThumbnail: Image?

    private enum VideoError: Error { case noClient }

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

    private func downloadVideo() async throws -> URL {
        guard let client = appState.matrixClient?.client else {
            throw VideoError.noClient
        }

        let handle = try await client.getMediaFile(
            mediaSource: content.source,
            filename: content.filename,
            mimeType: content.info?.mimetype ?? "",
            useCache: true,
            tempDir: NSTemporaryDirectory()
        )
        fileHandle = handle
        let path = try handle.path()
        return URL(filePath: path, directoryHint: .notDirectory)
    }

    func loadVideo(autoplay: Bool = true) async {
        do {
            let url: URL
            if let handle = fileHandle {
                url = URL(filePath: try handle.path(), directoryHint: .notDirectory)
            } else {
                url = try await downloadVideo()
            }
            video = AVPlayer(url: url)
            if autoplay { video?.play() }
        } catch {
            Logger.viewCycle.error("Failed to load video: \(error)")
        }
    }

    private func generateThumbnail() async {
        let cacheKey = NSString(string: "thumb:" + content.source.url())
        if let cached = MatrixClient.imageCache.object(forKey: cacheKey) {
            generatedThumbnail = Image(nsImage: cached)
            return
        }

        do {
            let url = try await downloadVideo()

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)

            let cgImage = try await generator.image(at: .zero).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            MatrixClient.imageCache.setObject(nsImage, forKey: cacheKey)
            generatedThumbnail = Image(nsImage: nsImage)
        } catch {
            Logger.viewCycle.error("Failed to generate video thumbnail: \(error)")
        }
    }

    @ViewBuilder
    var thumbnailView: some View {
        if let thumbnailSource = content.info?.thumbnailSource {
            MatrixImageView(mediaSource: thumbnailSource, mimeType: content.info?.thumbnailInfo?.mimetype)
        } else if let generatedThumbnail {
            generatedThumbnail.resizable().scaledToFit()
        } else if let blurhash = content.info?.blurhash,
                  let info = content.info,
                  let w = info.width, w > 0,
                  let h = info.height, h > 0,
                  let nsImage = NSImage.fromBlurHash(blurhash, size: CGSize(width: 32, height: Int(32 * CGFloat(h) / CGFloat(w)))) {
            Image(nsImage: nsImage).resizable().scaledToFit()
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
    }

    var body: some View {
        VStack {
            if let video {
                TimelineVideoPlayer(videoPlayer: video)
                    .cornerRadius(6)
            } else {
                Button(action: { Task { await loadVideo() } }) {
                    thumbnailView
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
        .frame(minHeight: content.info?.thumbnailSource == nil && generatedThumbnail == nil ? maxHeight : nil)
        .task(id: content.source.url()) {
            if content.info?.thumbnailSource == nil && generateVideoThumbnails {
                await generateThumbnail()
            }
        }
    }
}
