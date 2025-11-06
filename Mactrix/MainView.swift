import SwiftUI



struct RoomIcon: View {
    var body: some View {
        Rectangle()
            .aspectRatio(1.0, contentMode: .fit)
            .background(Color.blue)
    }
}

struct MainView: View {
    @Environment(AppState.self) var appState
    
    @State private var showWelcomeSheet: Bool = false
    @State private var selectedCategory: SelectedCategory = .defaultCategory
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SidebarSpacesView(selectedCategory: $selectedCategory)
            
            NavigationSplitView {
                SidebarChannelView(selectedCategory: selectedCategory)
            } detail: {
                ContentUnavailableView("Select a room", systemImage: "message.fill")
            }
            .background(Color(NSColor.controlBackgroundColor))
            .toolbarColorScheme(.light, for: .windowToolbar)
            .toolbar(removing: .title)
        }
        .task { await attemptLoadUserSession() }
        .sheet(isPresented: $showWelcomeSheet, onDismiss: {
            Task {
                try await Task.sleep(for: .milliseconds(100))
                if let matrixClient = appState.matrixClient {
                    onMatrixLoaded(matrixClient: matrixClient)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }) {
            WelcomeSheetView()
        }
        .onChange(of: appState.matrixClient == nil) { _, matrixClientIsNil in
            if matrixClientIsNil {
                showWelcomeSheet = true
                selectedCategory = .defaultCategory
            }
        }
    }
    
    func attemptLoadUserSession() async {
        do {
            if let matrixClient = try await MatrixClient.attemptRestore() {
                appState.matrixClient = matrixClient
            }
        } catch {
            print(error)
        }
        
        showWelcomeSheet = appState.matrixClient == nil
        if let matrixClient = appState.matrixClient {
            onMatrixLoaded(matrixClient: matrixClient)
        }
    }
    
    func onMatrixLoaded(matrixClient: MatrixClient) {
        Task {
            try await matrixClient.startSync()
        }
    }
}

#Preview {
    MainView()
}
