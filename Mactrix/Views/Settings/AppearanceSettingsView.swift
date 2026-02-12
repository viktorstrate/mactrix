import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("fontSize") var fontSize: Int = 13
    
    var body: some View {
        Form {
            Picker("Font size", selection: $fontSize) {
                ForEach(8..<25) {
                    Text("\($0)")
                        .tag($0)
                }
            }
        }
    }
}
