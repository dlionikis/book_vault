//
//  SleepTimerManager.swift
//  BookVault
//
//  Sleep timer: auto-pause playback after a duration or at the end of a chapter.
//

import Foundation

// MARK: - SleepTimerMode

/// What the timer is counting toward.
enum SleepTimerMode: Equatable {
    /// Pause after a fixed wall-clock interval.
    case duration(TimeInterval)
    /// Pause when the chapter that was playing at arm time ends.
    ///
    /// The boundary is captured when arming rather than re-resolved each tick:
    /// `getCurrentChapter()` matches `[startTime, endTime)`, so it returns nil
    /// the instant playback reaches the boundary. Re-resolving would make the
    /// timer fade to silence and then never fire.
    case endOfChapter(boundary: TimeInterval)
}

// MARK: - SleepTimerState

/// Timer lifecycle.
///
/// `fireDate` is the source of truth for `.duration` — deliberately an absolute
/// `Date` rather than a countdown that gets decremented. See `decide(now:...)`.
/// `.endOfChapter` carries no deadline; it resolves against playback position.
enum SleepTimerState: Equatable {
    case off
    case armed(mode: SleepTimerMode, fireDate: Date?)
    case fading(mode: SleepTimerMode, fireDate: Date?)
}

// MARK: - SleepTimerDecision

/// The action `AudioPlayerManager` should take on this audio tick.
enum SleepTimerDecision: Equatable {
    case none
    /// Entering the fade window; capture the current volume before ramping.
    case beginFade
    /// Continue ramping. `progress` runs 0.0 (fade start) → 1.0 (silent).
    case continueFade(progress: Double)
    /// Pause now.
    case fire
}

// MARK: - SleepTimerManager

/// Owns sleep-timer state. Deliberately knows nothing about `AVPlayer` — it
/// decides, the player acts.
///
/// **Why the deadline is a `Date` and not a countdown:** this timer runs for up
/// to 90 minutes, backgrounded, with the screen locked. A `Timer` is scheduled
/// on a RunLoop that stops when the app suspends, so it cannot be relied on to
/// fire — and a missed fire means the book plays all night, which is the exact
/// failure this feature exists to prevent. Instead `AudioPlayerManager` calls
/// `decide(now:...)` from its periodic `AVPlayer` time observer, which ticks
/// whenever audio is actually playing. If audio is playing, the check runs; if
/// it is not, there is nothing to pause. A late check pauses late by at most
/// one tick rather than never.
@MainActor
final class SleepTimerManager: ObservableObject {
    // MARK: - Shared

    static let shared = SleepTimerManager()

    // MARK: - Constants

    /// Seconds of fade-out before the pause.
    static let fadeDuration: TimeInterval = 10

    /// Selectable durations, in seconds.
    static let presets: [TimeInterval] = [8, 15, 30, 45, 60, 90].map { $0 * 60 }

    // MARK: - Published State

    @Published private(set) var state: SleepTimerState = .off

    // MARK: - Properties

    private let settings: PlaybackSettings

    // MARK: - Initialization

    /// Production singleton initializer.
    private convenience init() {
        self.init(settings: .shared)
    }

    /// Testable initializer.
    /// - Parameter settings: Store used to persist the last-used duration.
    init(settings: PlaybackSettings) {
        self.settings = settings
    }

    // MARK: - Computed Properties

    var isArmed: Bool {
        switch state {
        case .off: false
        case .armed, .fading: true
        }
    }

    var mode: SleepTimerMode? {
        switch state {
        case .off: nil
        case let .armed(mode, _), let .fading(mode, _): mode
        }
    }

    // MARK: - Control

    /// Arm the timer.
    /// - Parameters:
    ///   - mode: Duration or end-of-chapter.
    ///   - now: Injected clock. See the note on `decide(now:...)`.
    func arm(_ mode: SleepTimerMode, now: Date = Date()) {
        switch mode {
        case let .duration(interval):
            state = .armed(mode: mode, fireDate: now.addingTimeInterval(interval))
            // Remember the choice so the picker pre-selects it next time.
            settings.lastSleepTimerDuration = interval
        case .endOfChapter:
            state = .armed(mode: mode, fireDate: nil)
        }
    }

    /// Arm end-of-chapter for the chapter currently playing.
    /// - Returns: `false` if there is no chapter to pin to.
    @discardableResult
    func armEndOfChapter(chapter: Chapter?) -> Bool {
        guard let chapter else { return false }
        arm(.endOfChapter(boundary: chapter.endTime))
        return true
    }

    /// Disarm. The caller is responsible for restoring volume if a fade was in
    /// progress — this type does not touch the player.
    func cancel() {
        state = .off
    }

    /// Move from `.armed` to `.fading`. Called once, on the `.beginFade` edge.
    func beginFading() {
        guard case let .armed(mode, fireDate) = state else { return }
        state = .fading(mode: mode, fireDate: fireDate)
    }

    /// Push the deadline out and leave the fade window.
    ///
    /// Returns to `.armed` from `.fading`, so the caller must restore volume.
    func extend(by interval: TimeInterval, now: Date = Date()) {
        guard let mode else { return }

        switch mode {
        case .duration:
            // Extend from the later of the existing deadline or now, so
            // extending an already-expired timer still gives a full interval.
            let base: Date = {
                switch state {
                case let .armed(_, fireDate), let .fading(_, fireDate):
                    guard let fireDate else { return now }
                    return max(fireDate, now)
                case .off:
                    return now
                }
            }()
            state = .armed(
                mode: .duration(interval),
                fireDate: base.addingTimeInterval(interval)
            )
        case .endOfChapter:
            // No deadline to push; converting to a duration is the sane reading
            // of "give me more time".
            state = .armed(
                mode: .duration(interval),
                fireDate: now.addingTimeInterval(interval)
            )
        }
    }

    // MARK: - Decision

    /// Decide what the player should do on this tick.
    ///
    /// Pure: no side effects, and **no internal clock read**. `now` is a
    /// parameter so the full 90-minute behavior is testable in microseconds
    /// without real timers or a clock-protocol abstraction.
    ///
    /// - Parameters:
    ///   - now: Current wall-clock time.
    ///   - currentTime: Absolute playback position, in seconds.
    func decide(
        now: Date,
        currentTime: TimeInterval
    ) -> SleepTimerDecision {
        guard let mode else { return .none }

        let remaining: TimeInterval
        switch mode {
        case .duration:
            guard let fireDate = fireDate(of: state) else { return .none }
            remaining = fireDate.timeIntervalSince(now)
        case let .endOfChapter(boundary):
            // Measured in playback seconds against the boundary captured at arm
            // time, not wall clock, so it stays correct when the playback rate
            // changes mid-run.
            remaining = boundary - currentTime
        }

        // Checked first, so a deadline far in the past fires immediately rather
        // than being misread as "deep in the fade window". This is the
        // app-was-suspended case.
        if remaining <= 0 { return .fire }

        guard remaining <= Self.fadeDuration else { return .none }

        if case .armed = state { return .beginFade }

        let progress = 1.0 - (remaining / Self.fadeDuration)
        return .continueFade(progress: min(max(progress, 0), 1))
    }

    // MARK: - Formatting

    /// Label for the timer, shared by the player button and the lock-screen
    /// string so the two can never disagree.
    ///
    /// - Returns: `"12:45"` while counting down, `"Chapter"` for
    ///   end-of-chapter, or `nil` when off.
    static func countdownText(
        for state: SleepTimerState,
        now: Date,
        currentTime: TimeInterval = 0
    ) -> String? {
        let mode: SleepTimerMode
        let fireDate: Date?
        switch state {
        case .off:
            return nil
        case let .armed(activeMode, deadline), let .fading(activeMode, deadline):
            mode = activeMode
            fireDate = deadline
        }

        switch mode {
        case .duration:
            guard let fireDate else { return nil }
            return format(remaining: fireDate.timeIntervalSince(now))
        case let .endOfChapter(boundary):
            // Once inside the final stretch, a countdown is more useful than a
            // static label.
            let remaining = boundary - currentTime
            return remaining <= 60 ? format(remaining: remaining) : "Chapter"
        }
    }

    /// Remaining time as `m:ss` / `h:mm:ss`, clamped at zero.
    private static func format(remaining: TimeInterval) -> String {
        let total = Int(max(0, remaining).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Private Helpers

    private func fireDate(of state: SleepTimerState) -> Date? {
        switch state {
        case .off: nil
        case let .armed(_, fireDate), let .fading(_, fireDate): fireDate
        }
    }
}
