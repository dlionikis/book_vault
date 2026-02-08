//
//  SeriesListView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - SeriesListView

/// List view for browsing all series alphabetically
struct SeriesListView: View {
    var body: some View {
        BrowseListView(configuration: .series())
    }
}

// MARK: - SeriesListView_Previews

// periphery:ignore - Used by Xcode Previews
struct SeriesListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SeriesListView()
        }
        .previewDisplayName("Series List")

        NavigationView {
            SeriesListView()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Series List (Dark)")
    }
}
