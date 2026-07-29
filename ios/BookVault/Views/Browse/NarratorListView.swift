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

// MARK: - NarratorListView_Previews

// periphery:ignore - Used by Xcode Previews
struct NarratorListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NarratorListView()
        }
        .previewDisplayName("Narrator List")

        NavigationStack {
            NarratorListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Narrator List (Dark)")
    }
}
