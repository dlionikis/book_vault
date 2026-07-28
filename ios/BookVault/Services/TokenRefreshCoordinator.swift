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

    /// Incremented on every successful refresh. Callers capture this before
    /// issuing a request and pass it back if that request 401s; a value that has
    /// moved on means the token was already replaced while the request was in
    /// flight, so there is nothing left to refresh.
    private var generation: UInt64 = 0

    /// The current token generation. Capture this *before* issuing a request.
    func currentGeneration() -> UInt64 {
        generation
    }

    /// Perform a token refresh, join the one in progress, or skip it entirely if
    /// the token has already been replaced since `observedGeneration`.
    ///
    /// Exactly one caller runs `operation`; all others suspend until it
    /// finishes and then receive its result. Safe to call from any task.
    ///
    /// - Parameters:
    ///   - observedGeneration: the generation captured before the request that
    ///     just 401'd. Pass `nil` to force a refresh attempt regardless.
    ///   - operation: performs the actual refresh. Only invoked for the caller
    ///     that wins the claim.
    /// - Returns: whether a valid token is now available — `true` both for a
    ///   successful refresh and for a caller whose token was already renewed.
    func refresh(
        observedGeneration: UInt64? = nil,
        using operation: @Sendable () async -> Bool
    ) async -> Bool {
        // A request issued before some *completed* refresh can still 401 (it was
        // already in flight when the token was swapped). Its 401 is stale
        // information: the token is fresh now, so refreshing again would burn a
        // rotated refresh token for nothing — the very failure this type exists
        // to prevent. Tell the caller to just retry.
        if let observedGeneration, observedGeneration < generation {
            DebugLogger.auth("Token already refreshed since this request began - skipping redundant refresh")
            return true
        }

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

        // Bump before releasing the flag, so any caller that observed the
        // pre-refresh generation is correctly told to retry rather than refresh.
        if success {
            generation &+= 1
        }

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
