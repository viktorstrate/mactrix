import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("fontSize") var fontSize: Int = 16
    
    var body: some View {
        HStack {
            Picker("Font size", selection: $fontSize) {
                ForEach(8..<25) {
                    Text("\($0)")
                        .tag($0)
                }
            }
        }
    }
}
