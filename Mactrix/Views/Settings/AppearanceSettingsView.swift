import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("fontSize") var fontSize: Int = 13
    @AppStorage("generateVideoThumbnails") var generateVideoThumbnails: Bool = false

    var body: some View {
        Form {
            Picker("Font size", selection: $fontSize) {
                ForEach(8..<25) {
                    Text("\($0)")
                        .tag($0)
                }
            }
            Toggle("Generate video thumbnails", isOn: $generateVideoThumbnails)
                .help("Downloads videos to generate thumbnails when the server doesn't provide one. Also pre-caches videos for instant playback.")
        }
    }
}
