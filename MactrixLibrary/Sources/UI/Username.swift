import SwiftUI

struct Username: View {
    var id: String
    var name: String?
    
    var body: some View {
        Text(name ?? id).foregroundStyle(Color(userID: id))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(name ?? id)
            .textSelection(.enabled)
    }
}
