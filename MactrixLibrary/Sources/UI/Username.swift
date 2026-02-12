import SwiftUI
import Models

struct Username<Profile: UserProfile>: View {
    var userProfile: Profile
    
    var body: some View {
        Text(userProfile.displayName ?? userProfile.userId).foregroundStyle(Color(userID: userProfile.userId))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(userProfile.displayName ?? userProfile.userId)
            .textSelection(.enabled)
    }
}
