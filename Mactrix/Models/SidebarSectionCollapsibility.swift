//
//  SidebarSectionCollapsibility.swift
//  Mactrix
//
//  Created by Marquis Kurt on 17-02-2026.
//

/// A structure that describes the collapsed/expanded states of sections in the sidebar.
///
/// This is typically used in conjunction with `Section(_:isExpanded)` to allow users to expand or collapse sidebar
/// content. Each sidebar entry should have a corresponding entry in this structure.
///
/// ```swift
/// @Environment(WindowState.self) var windowState
///
/// Section("Favorites", isExpanded: $windowState.sidebarSections.favorites) { ... }
/// ```
///
/// > Note: You do not need to create this structure yourself. Rather, you should use the collapsibility information
/// > from ``WindowState/sidebarSections``.
struct SidebarSectionCollapsibility: Codable, Equatable {
    /// Whether the favorites section is expanded.
    var favorites = true

    /// Whether the direct messages section is expanded.
    var directs = true

    /// Whether the rooms section is expanded.
    var rooms = true

    /// Whether the spaces section is expanded.
    var spaces = true
}
