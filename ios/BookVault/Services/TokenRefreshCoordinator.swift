//
//  TokenRefreshCoordinator.swift
//  BookVault
//
//  Single-flight coordination for access-token refresh, shared by every path
//  that can take a 401 — the JSON API (`APIClient`) and the AVPlayer streaming
//  path (`AuthenticatedResourceLoader`).
//
//  Why this is shared rather than per-caller: the app previously had two
//  independent refresh implementations. PR #56 fixed coordination in APIClient
//  and PR #66 added a separate one to the resource loader, so neither knew
//  about the other's in-flight refresh. Because the backend rotates the refresh
//  token on every use, two concurrent refreshes mean the second presents an
//  already-consumed token, gets rejected, and the user is logged out
//  mid-playback. One coordinator for the whole app is what actually closes it.
//  See docs/plans/ios-audio-session-persistence-plan.md.
//

import Foundation

/// A latch that admits exactly one caller until it is reset.
///
/// Used to collapse the burst of force-logout calls that a single refresh
/// failure produces — every in-flight request that 401s reaches a logout path
/// independently, and without this each one tears the session down again.
actor OneShotGate {
    private var claimed = false

    /// Returns `true` for the first caller and `false` for every caller after,
    /// until `reset()`. The check and the claim are one atomic step.
    func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }

    /// Re-arm the gate. Called on a successful login so a later session can log
    /// out normally.
    func reset() {
        claimed = false
    }
}

/// Actor coordinating token refresh so that concurrent 401s trigger exactly one
/// refresh and every other caller awaits *that* refresh's result.
///
/// The whole check-and-claim decision happens inside a single actor-isolated
/// method (`refresh(using:)`). There is deliberately no public "is a refresh in
/// progress?" query: exposing one invites a check-then-act race, where two
/// callers both observe "no refresh running" across separate awaits and both
/// start one. That was the shape of the original bug.
actor TokenRefreshCoordinator {
    /// The app-wide coordinator. Every production 401 path must use this
    /// instance — `APIClient.shared` and the per-playback resource loaders —
    /// otherwise they refresh independently and the rotated refresh token gets
    /// consumed twice. Tests construct their own instances instead.
    static let shared = TokenRefreshCoordinator()

    /// Callers parked waiting on the in-flight refresh.
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    /// Whether a refresh is currently in flight.
    private var isRefreshing = false

    /// Perform a token refresh, or join the one already in progress.
    ///
    /// Exactly one caller runs `operation`; all others suspend until it
    /// finishes and then receive its result. Safe to call from any task.
    ///
    /// - Parameter operation: performs the actual refresh. Only invoked for the
    ///   caller that wins the claim.
    /// - Returns: whether the refresh succeeded — the same value for the
    ///   winning caller and every joiner.
    func refresh(using operation: @Sendable () async -> Bool) async -> Bool {
        // Claim-or-join is atomic: this runs to the first suspension point
        // without interleaving, so exactly one caller can observe
        // `isRefreshing == false` and flip it.
        if isRefreshing {
            DebugLogger.auth("Token refresh already in progress - joining it")
            // Registering the continuation is synchronous with respect to this
            // actor, so it cannot be appended after the array has been drained.
            // (Doing this from a detached Task was the original lost-wakeup bug:
            // a fast refresh could drain `waiters` before registration ran, and
            // that continuation was then never resumed — hanging the request.)
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        isRefreshing = true

        let success = await operation()

        // Take the waiters and reset state before resuming anyone, so a caller
        // that arrives during resumption starts a fresh refresh rather than
        // joining one that has already completed.
        let parked = waiters
        waiters.removeAll()
        isRefreshing = false

        if !parked.isEmpty {
            DebugLogger.auth("Token refresh completed (success: \(success)) - resuming \(parked.count) waiting request(s)")
        }

        for waiter in parked {
            waiter.resume(returning: success)
        }

        return success
    }
}
