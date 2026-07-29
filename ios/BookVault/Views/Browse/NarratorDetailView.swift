//
//  NarratorDetailView.swift
//  BookVault
//
//  Created by Claude Code on 12/28/25.
//

import SwiftUI

// MARK: - NarratorDetailView

/// Detail view showing a narrator and all their books
struct NarratorDetailView: View {
    let narratorId: String

    var body: some View {
        BrowseDetailView(itemId: narratorId, configuration: .narrator())
    }
}

// MARK: - NarratorDetailView_Previews

// periphery:ignore - Used by Xcode Previews
struct NarratorDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            // Note: Using a placeholder ID for preview
            NarratorDetailView(narratorId: "00000000-0000-0000-0000-000000000000")
        }
        .previewDisplayName("Narrator Detail")

        NavigationStack {
            NarratorDetailView(narratorId: "00000000-0000-0000-0000-000000000000")
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Narrator Detail (Dark)")
    }
}
