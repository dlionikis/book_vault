//
//  NarratorListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - NarratorListView

/// List view for browsing all narrators alphabetically
struct NarratorListView: View {
    var body: some View {
        BrowseListView(configuration: .narrators())
    }
}
// MARK: - Previews

#Preview("Narrator List") {
    NavigationStack {
        NarratorListView()
    }
}

#Preview("Narrator List (Dark)") {
    NavigationStack {
        NarratorListView()
    }
    .preferredColorScheme(.dark)
}
