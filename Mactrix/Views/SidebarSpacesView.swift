//
//  SidebarSpacesView.swift
//  Mactrix
//
//  Created by Viktor Strate Kløvedal on 31/10/2025.
//

import SwiftUI
import MatrixRustSDK

struct SidebarIcon<V: View>: View {
    
    let selected: Bool
    @ViewBuilder let content: V
    
    var body: some View {
        ZStack {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .background(.gray)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.controlAccentColor).opacity(selected ? 1 : 0), lineWidth: 3)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color(NSColor.windowBackgroundColor))
    }
}

struct SpaceIcon: View {
    let room: Room
    let selected: Bool
    
    @Environment(AppState.self) var appState
    
    @State private var icon: Image? = nil
    
    var nameInitials: String {
        guard let name = room.displayName() else { return "" }
        return String(name.prefix(2))
    }
    
    var body: some View {
        SidebarIcon(selected: selected) {
            if let icon = icon {
                icon.resizable()
            } else {
                Text(nameInitials)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard let avatarUrlStr = room.avatarUrl() else { return }
            //guard let avatarUrl = URL(string: avatarUrlStr) else { return }
            guard let matrixClient = appState.matrixClient?.client else { return }
            
            do {
                let data = try await matrixClient.getMediaContent(mediaSource: .fromUrl(url: avatarUrlStr))
                icon = try await Image(importing: data, contentType: nil)
            } catch {
                print("Failed to fetch space avatar: \(error)")
            }
        }
    }
}

struct RoomsIcon: View {
    let selected: Bool
    
    var body: some View {
        SidebarIcon(selected: selected) {
            Image(systemName: "number")
        }
    }
}

enum SelectedCategory: Hashable {
    case rooms
    case space(id: String)
    
    static var defaultCategory: Self { .rooms }
}

struct SidebarSpacesView: View {
    
    @Environment(AppState.self) var appState
    
    @Binding var selectedCategory: SelectedCategory
    
    var spaces: [Room] {
        let allRooms = appState.matrixClient?.rooms ?? []
        return allRooms.filter { $0.isSpace() }
    }
    
    private var selectedSpaceId: String? {
        if case let .space(id: selectedId) = self.selectedCategory {
            return selectedId
        } else {
            return nil
        }
    }
    
    var body: some View {
        List(selection: $selectedCategory) {
            RoomsIcon(selected: selectedCategory == .rooms)
                .tag(SelectedCategory.rooms)
                .help("Other rooms")
            
            Divider()
            
            ForEach(spaces) { room in
                SpaceIcon(room: room, selected: selectedCategory == .space(id: room.id()))
                    .tag(SelectedCategory.space(id: room.id()))
                    .help(room.displayName() ?? "Unknown space")
            }
        }
        .listStyle(.plain)
        .safeAreaPadding(.top, 6)
        .frame(width: 56)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay( Divider()
            .frame(maxWidth: 1, maxHeight: .infinity)
            .background(Color(NSColor.separatorColor)), alignment: .trailing)
    }
}

#Preview {
    SidebarSpacesView(selectedCategory: .constant(.defaultCategory))
}
