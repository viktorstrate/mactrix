import SwiftUI
import Models

struct Username: View {
    var userProfile: any UserProfile
    
    var body: some View {
        Text(userProfile.displayName ?? userProfile.userId).foregroundStyle(Color(userID: userProfile.userId))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(userProfile.displayName ?? userProfile.userId)
            .textSelection(.enabled)
    }
}
