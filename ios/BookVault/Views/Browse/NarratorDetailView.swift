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
// MARK: - Previews

#Preview("Narrator Detail") {
    NavigationStack {
        // Note: Using a placeholder ID for preview
        NarratorDetailView(narratorId: "00000000-0000-0000-0000-000000000000")
    }
}

#Preview("Narrator Detail (Dark)") {
    NavigationStack {
        NarratorDetailView(narratorId: "00000000-0000-0000-0000-000000000000")
    }
    .preferredColorScheme(.dark)
}
