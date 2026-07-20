//
//  RestoreRequestsView.swift
//  BookVault
//
//  Lists the user's archive-restore requests (in-progress + completed in the
//  last 7 days), mirroring the web /library/restores page. Reached from
//  Settings → Restore Requests. Auto-refreshes while any restore is active.
//

import SwiftUI

// MARK: - RestoreRequestsViewModel

/// Fetches and groups restore requests. Kept separate from the view so the
/// grouping/labeling logic is unit-testable without SwiftUI.
@MainActor
final class RestoreRequestsViewModel: ObservableObject {
    @Published private(set) var active: [RestoreRequestSummary] = []
    @Published private(set) var recent: [RestoreRequestSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var hasLoadedOnce = false

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    /// Any restore still in progress — drives the auto-refresh timer.
    var hasActive: Bool { !active.isEmpty }

    /// True only once a successful load returned zero requests.
    var isEmpty: Bool { hasLoadedOnce && !loadFailed && active.isEmpty && recent.isEmpty }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            let response = try await apiClient.listRestores()
            apply(response.restores)
            loadFailed = false
        } catch {
            loadFailed = true
            DebugLogger.error("Failed to load restore requests", error: error)
        }
    }

    /// Split the flat list into the two display buckets. `in_progress` →
    /// active; `completed` → recent. `failed` requests are surfaced under
    /// active too so the user sees the outcome (with a distinct label/subtitle).
    private func apply(_ all: [RestoreRequestSummary]) {
        active = all.filter { $0.status == .inProgress || $0.status == .failed }
        recent = all.filter { $0.status == .completed }
    }

    /// Subtitle for a request row.
    static func subtitle(for request: RestoreRequestSummary) -> String {
        switch request.status {
        case .inProgress:
            return ArchiveStatusFormatter.restoringDetail(estimatedCompletion: request.estimatedCompletion)
        case .completed:
            return "Ready to play"
        case .failed:
            return "Restore failed — tap to try again"
        }
    }
}

// MARK: - RestoreRequestsView

struct RestoreRequestsView: View {
    @StateObject private var viewModel = RestoreRequestsViewModel()

    // Poll every 30s while a restore is active (matches the web page cadence).
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if viewModel.isLoading, !viewModel.hasLoadedOnce {
                ProgressView("Loading restores…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.loadFailed, viewModel.active.isEmpty, viewModel.recent.isEmpty {
                errorState
            } else if viewModel.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Restore Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .onReceive(refreshTimer) { _ in
            guard viewModel.hasActive else { return }
            Task { await viewModel.load() }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: Sub-views

    private var list: some View {
        List {
            if !viewModel.active.isEmpty {
                Section("Restoring (\(viewModel.active.count))") {
                    ForEach(viewModel.active, id: \.id) { RestoreRequestRow(request: $0) }
                }
            }
            if !viewModel.recent.isEmpty {
                Section("Recently restored") {
                    ForEach(viewModel.recent, id: \.id) { RestoreRequestRow(request: $0) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No restore requests")
                .font(.headline)
            Text("When you request an archived audiobook, it'll show up here while it's being restored.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Couldn't load restores")
                .font(.headline)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RestoreRequestRow

private struct RestoreRequestRow: View {
    let request: RestoreRequestSummary

    var body: some View {
        NavigationLink(destination: BookDetailLoader(bookId: request.bookId.uuidString)) {
            HStack(spacing: 12) {
                CachedCoverImage(bookId: request.book.id, coverUrl: request.book.coverUrl)
                    .frame(width: 44, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.book.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(RestoreRequestsViewModel.subtitle(for: request))
                        .font(.caption)
                        .foregroundColor(request.status == .failed ? .red : .secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if request.status == .inProgress {
                    ProgressView()
                } else if request.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }
}
