//
//  ArchiveStatusView.swift
//  BookVault
//
//  Phase 7a: shared UI for the S3 archive/restore workflow.
//
//  A book's audio can be in one of three states (derived from the cached
//  `audio_availability` column, self-healed at play time):
//    - available: ready to stream/download immediately
//    - archived:  in the S3 Intelligent-Tiering Archive Access tier; a ~3-5h
//                 restore is required before it can be played or downloaded
//    - restoring: a restore is in flight
//
//  This file centralises the human-readable strings, the badge shown on book
//  cards, and the estimated-completion formatting so every surface (grid items,
//  detail CTA, download button, player) reads consistently.
//

import SwiftUI

// MARK: - ArchiveStatusFormatter

/// Copy + time formatting shared across the archive/restore UI.
enum ArchiveStatusFormatter {
    /// A relative "ready in ~Xh" phrase for a restore in progress, or a generic
    /// fallback when the estimated completion is unknown.
    static func restoringDetail(estimatedCompletion: Date?) -> String {
        guard let eta = estimatedCompletion else {
            return "This can take 3–5 hours. We'll notify you when it's ready."
        }
        let remaining = eta.timeIntervalSinceNow
        if remaining <= 0 {
            return "Finishing up — this should be ready any moment."
        }
        let hours = Int((remaining / 3600).rounded(.up))
        if hours <= 1 {
            return "Estimated ready in about an hour. We'll notify you when it's done."
        }
        return "Estimated ready in about \(hours) hours. We'll notify you when it's done."
    }
}

// MARK: - ArchiveBadge

/// Small pill overlaid on a book cover indicating the audio isn't immediately
/// playable. Renders nothing when the book is available (the common case).
struct ArchiveBadge: View {
    let status: Book.ArchiveStatus?

    var body: some View {
        switch status {
        case .archived:
            badge(systemImage: "archivebox.fill", text: "Archived", tint: .secondary)
        case .restoring:
            badge(systemImage: "clock.arrow.circlepath", text: "Restoring", tint: .orange)
        case .available, .none:
            // Available (or unknown → treat as available): no badge.
            EmptyView()
        }
    }

    private func badge(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .foregroundColor(tint)
        .clipShape(Capsule())
        .padding(6)
    }
}

// MARK: - BookRestoreCTA

/// Call-to-action shown on the book detail page in place of Play/Download when
/// the audio is archived in cold storage.
///
/// - archived → a "Request restore" button that POSTs `/restore` and flips to…
/// - restoring → a progress indicator with the estimated-ready time, polling
///   `/restore-status` every 30s. When the restore completes, prompts the user
///   to reload the book (a fresh fetch will report `available`).
struct BookRestoreCTA: View {
    let book: Book

    /// Local override of the book's server-provided archiveStatus so the button
    /// can react immediately to a restore request / poll result without needing
    /// the parent view to refetch.
    @State private var status: RestoreStatus.Status
    @State private var estimatedCompletion: Date?
    @State private var isRequesting = false
    @State private var errorMessage: String?

    private let apiClient: any APIClientProtocol
    // 30s poll cadence while a restore is in progress.
    private let pollTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(book: Book, apiClient: any APIClientProtocol = APIClient.shared) {
        self.book = book
        self.apiClient = apiClient
        // Seed from the book's cached archive status (absent → available).
        switch book.archiveStatus {
        case .archived: _status = State(initialValue: .archived)
        case .restoring: _status = State(initialValue: .restoring)
        case .available, .none: _status = State(initialValue: .available)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            switch status {
            case .archived:
                archivedButton
            case .restoring:
                restoringIndicator
            case .available:
                availableNotice
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onReceive(pollTimer) { _ in
            // Only poll while restoring; otherwise the timer is a no-op.
            guard status == .restoring else { return }
            Task { await refreshStatus() }
        }
    }

    // MARK: Sub-views

    private var archivedButton: some View {
        Button {
            Task { await requestRestore() }
        } label: {
            HStack {
                if isRequesting {
                    ProgressView().padding(.trailing, 4)
                } else {
                    Image(systemName: "arrow.clockwise.icloud")
                }
                Text(isRequesting ? "Requesting…" : "Request Restore")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isRequesting)
    }

    private var restoringIndicator: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView().padding(.trailing, 4)
                Text("Restoring from archive…")
                    .foregroundColor(.primary)
            }
            Text(ArchiveStatusFormatter.restoringDetail(estimatedCompletion: estimatedCompletion))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var availableNotice: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Ready to play — reopen this book")
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Actions

    private func requestRestore() async {
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        do {
            let response = try await apiClient.restoreBook(bookId: book.id)
            if response.status == .available {
                status = .available
            } else {
                status = .restoring
                estimatedCompletion = response.estimatedCompletion
            }
        } catch {
            errorMessage = "Couldn't start the restore. Please try again."
            DebugLogger.error("Restore request failed", error: error)
        }
    }

    private func refreshStatus() async {
        do {
            let result = try await apiClient.getBookRestoreStatus(bookId: book.id)
            status = result.status
            estimatedCompletion = result.estimatedCompletion
            if result.status == .archived, let lastError = result.lastError {
                errorMessage = "Previous restore failed: \(lastError)"
            }
        } catch {
            DebugLogger.error("Restore-status poll failed", error: error)
        }
    }
}

// MARK: - Previews

#Preview("Archived") {
    ArchiveBadge(status: .archived)
        .padding()
        .background(Color.gray)
}

#Preview("Restoring") {
    ArchiveBadge(status: .restoring)
        .padding()
        .background(Color.gray)
}
