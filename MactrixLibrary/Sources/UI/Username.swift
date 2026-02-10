import SwiftUI

struct Username: View {
    var id: String
    var name: String?
    
    var body: some View {
        Text(name ?? id).foregroundStyle(Color(userID: id))
    }
}
