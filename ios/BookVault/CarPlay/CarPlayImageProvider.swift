//
//  CarPlayImageProvider.swift
//  BookVault
//
//  CarPlay task B1 — cover art for list rows.
//

import UIKit

/// Supplies row artwork, downsampled for the head unit.
///
/// Two things drive the shape here:
///
/// 1. `CoverCacheManager.getCover(for:)` is synchronous and **cache-only** — it
///    returns `nil` on a miss rather than fetching. So a hit can fill the row
///    immediately, and a miss needs an async fetch plus a row update.
/// 2. CarPlay expects modestly-sized images. Handing it a full-resolution cover
///    wastes memory on every row and can be rejected at render time.
@MainActor
struct CarPlayImageProvider {
    /// Point size for list-row artwork. CarPlay renders row images small; this
    /// is deliberately conservative, and the head unit scales for its own
    /// display density.
    static let rowImageSize = CGSize(width: 60, height: 60)

    private let coverCache: any CoverCaching

    init(coverCache: any CoverCaching = CoverCacheManager.shared) {
        self.coverCache = coverCache
    }

    /// Deliver a cover for a row, now if it is cached and later if it is not.
    ///
    /// `completion` may be called twice: once synchronously with a cached image,
    /// and never again; or once asynchronously after a fetch. It is always
    /// called on the main actor, so callers can assign straight to a
    /// `CPListItem`.
    func loadCover(
        bookId: UUID,
        url: URL?,
        completion: @escaping (UIImage?) -> Void
    ) {
        if let cached = coverCache.getCover(for: bookId) {
            completion(Self.downsample(cached))
            return
        }

        guard let url else {
            completion(nil)
            return
        }

        // Miss: leave the row art-less for now and fill it in when the fetch
        // lands. Rows render immediately either way.
        Task {
            do {
                try await coverCache.cacheCover(for: bookId, from: url)
                let image = coverCache.getCover(for: bookId).map { Self.downsample($0) }
                completion(image)
            } catch {
                DebugLogger.warning("CarPlay: cover fetch failed for \(bookId): \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    /// Scale a cover down to `rowImageSize`, preserving aspect ratio.
    ///
    /// Covers are square in practice, but this does not assume that — a
    /// non-square image is fitted rather than squashed.
    static func downsample(_ image: UIImage, to target: CGSize = rowImageSize) -> UIImage {
        let scale = min(target.width / image.size.width, target.height / image.size.height)

        // Never upscale: a cover smaller than the row is left alone rather than
        // blown up into a blurry one.
        guard scale < 1 else { return image }

        let size = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
