//
//  CachedCoverImage.swift
//  BookVault
//
//  Created by Claude Code on 12/31/25.
//  Phase 2: Cover Image Caching for Presigned URLs
//

import SwiftUI

/// Cover image view that uses local cache, falling back to network download
/// This solves the presigned URL expiry problem by caching images by book ID
struct CachedCoverImage: View {
    let bookId: UUID
    let coverUrl: String?

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
            } else if loadFailed {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundColor(.gray)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
            }
        }
        .task(id: bookId) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        // Reset state for new book
        image = nil
        isLoading = false
        loadFailed = false

        let cache = CoverCacheManager.shared

        // Check cache first
        if let cached = cache.getCover(for: bookId) {
            image = cached
            return
        }

        // No cache - try to download
        guard let urlString = coverUrl, let url = URL(string: urlString) else {
            loadFailed = true
            return
        }

        isLoading = true

        do {
            try await cache.cacheCover(for: bookId, from: url)
            image = cache.getCover(for: bookId)
        } catch {
            DebugLogger.error("Failed to load cover for \(bookId)", error: error)
            loadFailed = true
        }

        isLoading = false
    }
}

// MARK: - Preview

#Preview("Cached Cover Image") {
    VStack(spacing: 20) {
        // With mock URL
        CachedCoverImage(
            bookId: UUID(),
            coverUrl: "https://example.com/cover.jpg"
        )
        .frame(width: 150, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        // Without URL (placeholder)
        CachedCoverImage(
            bookId: UUID(),
            coverUrl: nil
        )
        .frame(width: 150, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding()
}
