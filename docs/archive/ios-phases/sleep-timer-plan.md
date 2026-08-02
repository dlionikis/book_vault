# Sleep Timer — Implementation Plan (iOS)

> **Status**: ✅ **Implemented.** Phases 1–7 complete; `validate:full` green
> (804 iOS tests, SwiftLint strict, web suites, contract tests).
> Remaining: the on-device manual pass in §7.3 — it **cannot** be done in the
> simulator and is the real acceptance test.
> **Spec**: [sleep-timer-spec.md](./sleep-timer-spec.md) — read that for _what_ and _why_.
> This document is the _how_: exact files, signatures, insertion points, diffs.

---

## 0. Decisions as built

All six planned decisions held. Four things changed during implementation —
§0.1 records them, since the code no longer matches the plan text below.

| #   | Decision                                                                 | Where     | Outcome                          |
| --- | ------------------------------------------------------------------------ | --------- | -------------------------------- |
| 1   | Lock-screen countdown rides on the **album line**                        | §5.4      | ✅ as planned                    |
| 2   | Sleep button gets its **own row**; `GeometryReader` fractions rebalanced | §6.1      | ✅ as planned, verified visually |
| 3   | `AudioPlayerManaging` protocol is **not** modified                       | §4.2      | ✅ as planned                    |
| 4   | Fade ramps `player.volume`, published `volume` untouched                 | §5.2      | ✅ as planned                    |
| 5   | Manual pause does **not** cancel the timer                               | §5.1      | ✅ as planned                    |
| 6   | Timer does **not** survive app relaunch                                  | spec §8.1 | ✅ as planned                    |

### 0.1 Changes from the plan

**1. `endOfChapter` carries the boundary — a real bug the plan would have shipped.**

Planned: `.endOfChapter` with no associated value, re-resolving the chapter from
`getCurrentChapter()` on every tick. That is broken. `getCurrentChapter()`
matches `[startTime, endTime)`, so it returns `nil` the instant playback reaches
the boundary — `decide` would return `.none`, and the timer would fade to
silence and **never fire**. On a last chapter it would play to the end of the
book.

As built: `case endOfChapter(boundary: TimeInterval)`, captured when arming via
`armEndOfChapter(chapter:)`. `decide` compares against the captured boundary and
no longer takes a `currentChapter` parameter at all. Regression tests:
`testDecideEndOfChapter_PastBoundary_StillFires` and
`testSleepTimerEndOfChapter_FiresAtBoundary`.

**2. `xcodegen generate` IS required.** The plan said no project regeneration was
needed because the `sources` globs already cover the new directories. The globs
do cover them, but the `.xcodeproj` is generated and does not pick up new files
until regenerated — the first build failed with "cannot find 'SleepTimerManager'
in scope". Run `cd ios && xcodegen generate` after adding files.

**3. The a11y identifier does not work on this screen.** `NowPlayingView` sets
`.accessibilityIdentifier(A11y.NowPlaying.root)` on its root container, and
SwiftUI propagates that to every descendant — so **every** button on the player
(including the pre-existing speed button) reports `nowPlaying.root`. This is
pre-existing, not introduced here. `A11y.NowPlaying.sleepTimer` is still declared
in both files (parity test satisfied) and kept for intent, but `SleepTimerUITests`
matches on the accessibility **label** instead. Documented at the call site.

**4. "Turn Off" moved above the presets.** Planned as the last section. In the
armed state the countdown header takes the top third of the sheet, which pushed
turn-off below the fold past six presets and End of Chapter — unreachable
without scrolling. Since killing a running timer is the most likely reason to
reopen the sheet, it now sits directly under the header. Caught by
`testTurningTimerOffReturnsButtonToIdle`.

---

## 1. File manifest

### New files (4)

| Path                                                                | Lines (est.) |
| ------------------------------------------------------------------- | ------------ |
| `ios/BookVault/Services/SleepTimerManager.swift`                    | ~190         |
| `ios/BookVault/Views/Components/SleepTimerPicker.swift`             | ~170         |
| `ios/BookVaultTests/Services/Real/SleepTimerManagerRealTests.swift` | ~260         |
| `ios/BookVaultTests/Services/PlaybackSettingsTests.swift`           | ~90          |

### Modified files (5)

| Path                                                   | Change                                            |
| ------------------------------------------------------ | ------------------------------------------------- |
| `ios/BookVault/Services/PlaybackSettings.swift`        | +1 stored preference                              |
| `ios/BookVault/Services/AudioPlayerManager.swift`      | timer check in observer, fade, Now Playing suffix |
| `ios/BookVault/Views/Player/NowPlayingView.swift`      | button + sheet + layout rebalance                 |
| `ios/BookVault/Support/AccessibilityIdentifiers.swift` | +1 identifier                                     |
| `ios/BookVaultUITests/A11yID.swift`                    | +1 identifier (parity)                            |

### Explicitly NOT modified

- `Services/Protocols/AudioPlayerManaging.swift` — see §4.2
- `BookVaultTests/Mocks/MockAudioPlayerManager.swift` — follows from the above
- `CarPlay/CarPlayNowPlaying.swift` — inherits the lock-screen string for free
- No new build target, no `ActivityKit`, no `Info.plist` change

**No `project.yml` change needed** — all new files land inside directories
already covered by the `sources` globs. **`xcodegen generate` IS required**
though: the `.xcodeproj` is generated and won't see new files until you re-run
it. See §0.1.2.

---

## 2. Dependency order

```
Phase 1  SleepTimerManager + tests          ← no dependencies, pure model
Phase 2  PlaybackSettings + tests           ← independent of Phase 1
Phase 3  AudioPlayerManager wiring          ← needs 1
Phase 4  End-of-chapter mode                ← needs 3
Phase 5  UI (picker, button, layout)        ← needs 1, 2
Phase 6  Lock-screen countdown              ← needs 3
Phase 7  UI tests + manual device pass      ← needs everything
```

Phases 1 and 2 are parallelizable and independently mergeable — both are pure
model code with tests and no UI surface.

---

## 3. Phase 1 — `SleepTimerManager`

**New file**: `ios/BookVault/Services/SleepTimerManager.swift`

### 3.1 Types

```swift
import Foundation

/// What the timer is counting toward.
enum SleepTimerMode: Equatable {
    case duration(TimeInterval)
    case endOfChapter
}

/// Timer lifecycle. `fireDate` is the source of truth for `.duration`;
/// `.endOfChapter` has no deadline and is resolved against playback position.
enum SleepTimerState: Equatable {
    case off
    case armed(mode: SleepTimerMode, fireDate: Date?)
    case fading(mode: SleepTimerMode, fireDate: Date?)
}

/// The decision returned to AudioPlayerManager on each audio tick.
enum SleepTimerDecision: Equatable {
    case none
    case beginFade
    /// Ramp the fade. `progress` is 0.0 (fade start) → 1.0 (silent).
    case continueFade(progress: Double)
    case fire
}
```

### 3.2 Class

```swift
@MainActor
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    static let fadeDuration: TimeInterval = 10
    static let presets: [TimeInterval] = [8, 15, 30, 45, 60, 90].map { $0 * 60 }

    @Published private(set) var state: SleepTimerState = .off

    private let settings: PlaybackSettings

    private convenience init() { self.init(settings: .shared) }

    init(settings: PlaybackSettings) { self.settings = settings }
}
```

### 3.3 Public API

```swift
var isArmed: Bool
var mode: SleepTimerMode?

func arm(_ mode: SleepTimerMode, now: Date = Date())
func cancel()
func extend(by interval: TimeInterval, now: Date = Date())

/// Pure. No side effects, no internal clock read.
func decide(
    now: Date,
    currentTime: TimeInterval,
    currentChapter: Chapter?
) -> SleepTimerDecision

/// Shared by the player button and the lock-screen string.
static func countdownText(
    for state: SleepTimerState,
    now: Date,
    currentTime: TimeInterval = 0,
    currentChapter: Chapter? = nil
) -> String?
```

**`now` is always a parameter, never read internally.** This is the single most
important design point in the file: it makes 90-minute behavior testable in
microseconds and removes any need for a clock-protocol abstraction.

`arm(.duration(t))` also writes `settings.lastSleepTimerDuration = t`.
`arm(.endOfChapter)` does not touch the setting.

### 3.4 `decide` logic

```swift
func decide(now: Date, currentTime: TimeInterval, currentChapter: Chapter?) -> SleepTimerDecision {
    switch state {
    case .off:
        return .none

    case let .armed(mode, fireDate), let .fading(mode, fireDate):
        switch mode {
        case .duration:
            guard let fireDate else { return .none }
            let remaining = fireDate.timeIntervalSince(now)
            if remaining <= 0 { return .fire }
            if remaining <= Self.fadeDuration {
                let progress = 1.0 - (remaining / Self.fadeDuration)
                if case .armed = state { return .beginFade }
                return .continueFade(progress: min(max(progress, 0), 1))
            }
            return .none

        case .endOfChapter:
            guard let chapter = currentChapter else { return .none }
            let remaining = chapter.endTime - currentTime
            if remaining <= 0 { return .fire }
            if remaining <= Self.fadeDuration {
                let progress = 1.0 - (remaining / Self.fadeDuration)
                if case .armed = state { return .beginFade }
                return .continueFade(progress: min(max(progress, 0), 1))
            }
            return .none
        }
    }
}
```

Notes:

- `remaining <= 0` is checked **first**, so a deadline hours in the past fires
  immediately rather than being read as "deep in the fade window". This is the
  suspended-app case and the reason the whole design works.
- End-of-chapter fade is measured in **playback seconds**, not wall-clock, so it
  stays correct at 1.5×. At 2× a 10s fade covers 20s of audio; acceptable, and
  noted in spec §7.
- `.beginFade` is emitted once (on the `.armed` → `.fading` edge); the caller
  transitions state and subsequent ticks return `.continueFade`.

### 3.5 State transitions the caller drives

| Decision           | Caller does                                    | Then sets state to    |
| ------------------ | ---------------------------------------------- | --------------------- |
| `.none`            | nothing                                        | unchanged             |
| `.beginFade`       | capture `preFadeVolume`                        | `.fading`             |
| `.continueFade(p)` | `player.volume = preFade * (1 - p)`            | unchanged             |
| `.fire`            | `pause()`, restore volume, refresh Now Playing | `.off` via `cancel()` |

`extend(by:)` pushes `fireDate` **and** drops `.fading` back to `.armed`. The
caller must restore volume on that transition — covered by a test.

### 3.6 Tests — `SleepTimerManagerRealTests.swift`

Template: `ThemeManagerRealTests.swift`. All synchronous, no `Task.sleep`, no
real timers.

```
arm_duration_setsFireDateAtNowPlusInterval
arm_duration_persistsLastUsedDuration
arm_endOfChapter_doesNotPersistDuration
decide_beforeDeadline_returnsNone
decide_insideFadeWindow_returnsBeginFade
decide_whenAlreadyFading_returnsContinueFadeWithProgress
decide_atDeadline_returnsFire
decide_deadline40MinutesInPast_returnsFire        ← the suspended-app case
decide_whenOff_returnsNone
decide_endOfChapter_beforeBoundary_returnsNone
decide_endOfChapter_atBoundary_returnsFire
decide_endOfChapter_withNilChapter_neverFires
extend_pushesDeadline
extend_whileFading_returnsToArmed
cancel_returnsToOff
arm_whileArmed_replacesDeadline
countdownText_formatsMinutesSecondsZeroPadded
countdownText_returnsChapterLabelForEndOfChapter
countdownText_returnsNilWhenOff
countdownText_clampsAtZeroNotNegative
```

`decide_deadline40MinutesInPast_returnsFire` is the acceptance test for the core
design. If it ever regresses, the feature is broken in the exact way it exists
to prevent.

---

## 4. Phase 2 — `PlaybackSettings`

### 4.1 Diff

Follows the existing `defaultPlaybackRate` pattern exactly
(`PlaybackSettings.swift:24-51`) — `@Published` + `didSet` write-through, plus
existence-check-then-clamp on load.

```swift
// alongside defaultPlaybackRateKey
private static let lastSleepTimerDurationKey = "lastSleepTimerDuration"
private static let defaultSleepTimerDuration: TimeInterval = 30 * 60

/// Last sleep-timer duration the user picked, pre-selected in the picker.
@Published var lastSleepTimerDuration: TimeInterval {
    didSet {
        userDefaults.set(lastSleepTimerDuration, forKey: Self.lastSleepTimerDurationKey)
    }
}
```

In `init(userDefaults:)`:

```swift
if userDefaults.object(forKey: Self.lastSleepTimerDurationKey) != nil {
    let saved = userDefaults.double(forKey: Self.lastSleepTimerDurationKey)
    // Snap to a known preset; a value outside the set can't be represented in the picker.
    self.lastSleepTimerDuration = SleepTimerManager.presets.contains(saved)
        ? saved
        : Self.defaultSleepTimerDuration
} else {
    self.lastSleepTimerDuration = Self.defaultSleepTimerDuration
}
```

The existence check matters for the same reason as the rate: `0.0` is a valid
`Double` but not a valid duration.

### 4.2 On the protocol — decision #3

`AudioPlayerManaging` and `MockAudioPlayerManager` are **not** touched. Views
observe `SleepTimerManager.shared` directly, exactly as they already observe
`AudioPlayerManager.shared`.

Rationale: adding to the protocol forces a `MockAudioPlayerManager` update or the
34-test mock suite stops compiling, and buys nothing — no view needs sleep state
_through_ the player. `SleepTimerManager` is independently injectable for tests
on its own terms.

### 4.3 Tests — `PlaybackSettingsTests.swift` (new)

Uses a per-test `UserDefaults(suiteName:)`, as `ThemeManagerRealTests` does.

```
lastSleepTimerDuration_defaultsTo30Minutes
lastSleepTimerDuration_roundTripsThroughUserDefaults
lastSleepTimerDuration_snapsNonPresetValueToDefault
lastSleepTimerDuration_zeroStoredValueFallsBackToDefault
defaultPlaybackRate_stillRoundTrips              ← regression guard
```

---

## 5. Phase 3, 4, 6 — `AudioPlayerManager`

### 5.1 New private state

Near the existing private properties (`AudioPlayerManager.swift:107-122`):

```swift
private let sleepTimer: SleepTimerManager
/// Volume before the fade began, restored on every exit path.
private var preFadeVolume: Float?
/// Last mm:ss written to Now Playing; rate-limits the lock-screen update.
private var lastRenderedCountdown: String?
```

Add `sleepTimer: SleepTimerManager = .shared` to the testable init (`:149`) and
pass `.shared` from the production convenience init (`:134`).

**Cancellation points** — `cancel()` plus `restoreVolumeAfterFade()`:

- `play(book:)` — new listening session
- `stop()`
- `playerDidFinishPlaying` — book ended

`pause()` is deliberately **not** a cancellation point (decision #5, Audible
behavior: pausing to answer a question shouldn't kill your sleep timer).

### 5.2 Fade — decision #4

```swift
private func applyFade(progress: Double) {
    if preFadeVolume == nil { preFadeVolume = player?.volume ?? volume }
    guard let base = preFadeVolume else { return }
    player?.volume = base * Float(1.0 - progress)
}

private func restoreVolumeAfterFade() {
    guard let base = preFadeVolume else { return }
    player?.volume = base
    preFadeVolume = nil
}
```

Ramps `player.volume` directly, **never** the published `volume`. The published
property is bound to the volume slider (`NowPlayingView.swift:200-206`); driving
it during a fade would make the slider visibly crawl to zero and persist a bogus
value that survives the fade.

`restoreVolumeAfterFade()` must be called on **every** exit path — fire, cancel,
extend, new book, stop. A volume stuck at zero is the nastiest failure mode this
feature can produce, because it looks like "the app is broken" with no obvious
cause. Explicitly tested.

Steps land on the existing 0.5s observer — 20 steps over 10s, smooth enough for a
volume ramp, and no second timer.

### 5.3 Observer hook

Inside the existing periodic time observer (`AudioPlayerManager.swift:907-925`),
**after** the chapter-change block:

```swift
// Sleep timer: deadline is checked here rather than on a Timer because this
// observer is driven by AVPlayer and keeps ticking while backgrounded/locked.
switch self.sleepTimer.decide(
    now: Date(),
    currentTime: self.currentTime,
    currentChapter: self.getCurrentChapter()
) {
case .none:
    break
case .beginFade:
    self.sleepTimer.beginFading()
    self.applyFade(progress: 0)
case let .continueFade(progress):
    self.applyFade(progress: progress)
case .fire:
    self.sleepTimer.cancel()
    self.restoreVolumeAfterFade()
    self.pause()
    self.lastRenderedCountdown = nil
    self.updateNowPlayingInfo()
}

self.updateNowPlayingSleepTimerIfNeeded()
```

Order matters on `.fire`: **restore volume before `pause()`**, so a crash between
the two can't leave a silent player.

### 5.4 Lock-screen countdown — decision #1

`MPNowPlayingInfoCenter` has no field for auxiliary text (spec §3.4), so the
countdown rides on the album line.

Two pieces. First, a helper so full refreshes don't drop the countdown:

```swift
/// Album line, with the sleep countdown appended when armed.
/// Returns `base` unchanged when the timer is off — this is strictly additive.
private func albumTitle(base: String) -> String {
    guard let countdown = SleepTimerManager.countdownText(
        for: sleepTimer.state,
        now: Date(),
        currentTime: currentTime,
        currentChapter: getCurrentChapter()
    ) else { return base }
    return "\(base) · 💤 \(countdown)"
}
```

Applied at both `MPMediaItemPropertyAlbumTitle` assignments in
`updateNowPlayingInfo()` (`:366` and `:369`).

Second, the cheap per-tick update:

```swift
/// Mutates only the album key. Full `updateNowPlayingInfo()` re-runs the artwork
/// lookup and chapter arithmetic — far too heavy to run once per second.
private func updateNowPlayingSleepTimerIfNeeded() {
    guard sleepTimer.isArmed, let book = currentBook else { return }
    guard let countdown = SleepTimerManager.countdownText(
        for: sleepTimer.state, now: Date(),
        currentTime: currentTime, currentChapter: getCurrentChapter()
    ) else { return }
    guard countdown != lastRenderedCountdown else { return }   // 0.5s ticks → half are redundant
    lastRenderedCountdown = countdown

    let base = getCurrentChapter() != nil
        ? book.title
        : (book.series?.first?.title ?? "Audiobook")

    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyAlbumTitle] = "\(base) · 💤 \(countdown)"
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
}
```

The `countdown != lastRenderedCountdown` guard is what makes this 1Hz instead of
2Hz. `lastRenderedCountdown` is cleared on fire and cancel.

**The `base` string is duplicated** from `updateNowPlayingInfo()` (`:366`/`:369`).
Extract a small `private var albumBaseTitle: String` used by both rather than
letting the two drift.

### 5.5 Tests — extend `AudioPlayerManagerRealTests.swift`

Uses the existing `skipAudioSetup: true` init (`:129`), with an injected
`SleepTimerManager` on a private `UserDefaults` suite.

```
sleepTimer_fire_pausesPlayback
sleepTimer_fire_restoresPreFadeVolume            ← §5.2 regression guard
sleepTimer_cancel_restoresPreFadeVolume
sleepTimer_extendWhileFading_restoresVolume
sleepTimer_playDifferentBook_cancelsTimer
sleepTimer_manualPause_doesNotCancelTimer
sleepTimer_endOfChapter_firesAtBoundary

nowPlaying_albumLineUnchangedWhenTimerOff        ← "strictly additive" guard
nowPlaying_albumLineContainsCountdownWhenArmed
nowPlaying_albumLineCleanAfterFire
nowPlaying_fullRefreshWhileArmedKeepsCountdown
```

`MPNowPlayingInfoCenter.default().nowPlayingInfo` is readable in tests, so these
assert against the real dictionary.

---

## 6. Phase 5 — UI

### 6.1 Layout — decision #2, the one that needs a look

The spec assumed the sleep button could join the existing speed row. **Reading
the code, it can't.** That row (`NowPlayingView.swift:194-227`) is:

```
HStack(spacing: 20) {
    HStack { volume icon + Slider }     // greedy, takes all remaining width
    Button { speedometer + "1.5x" }     // ~90pt pill
}
```

The volume `Slider` is greedy. Adding a third element leaves the slider unusably
narrow on a 375pt-wide device, and the armed sleep pill is _wider_ than the speed
pill (`💤 12:45` vs `1.5x`). So the sleep button gets its **own row**.

Current fractions: `0.05 + 0.40 + 0.12 + 0.03 + 0.10 + 0.15 + 0.10 + 0.08 = 1.03`
(already slightly over 1.0; the trailing `Spacer` absorbs it).

Proposed — take 5% from cover art, 1% from the bottom spacer, to fund a 6% row:

| Element         | Current   | Proposed  |
| --------------- | --------- | --------- |
| Cover art       | 0.40      | **0.35**  |
| Sleep timer row | —         | **0.06**  |
| Bottom spacer   | 0.08      | **0.07**  |
| _(all others)_  | unchanged | unchanged |

New total: 1.03 (unchanged). Cover art at 0.35 matches the pre-existing value
noted in the comment at `:42` ("increased from 35%"), so this reverts a
deliberate change — worth a visual check on a large device.

**Alternative if 0.35 looks too small**: put the sleep button in the toolbar
(`.toolbar { ToolbarItem(placement: .topBarTrailing) }`) instead. Costs no
vertical space at all and the countdown is still glanceable, but it's less
discoverable and diverges from where Audible puts it. Flagging rather than
deciding — this is a taste call best made looking at the screen.

### 6.2 The button

New row, inserted after the speed/volume `HStack` (after `:229`):

```swift
// Sleep timer row - 6% of screen height
HStack {
    Button {
        showingSleepTimerPicker = true
    } label: {
        HStack(spacing: 6) {
            Image(systemName: sleepTimer.isArmed ? "moon.zzz.fill" : "moon.zzz")
                .font(.body)
            Text(sleepButtonLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()          // stops the pill twitching as digits change
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(sleepTimer.isArmed ? 0.30 : 0.15))
        .cornerRadius(8)
    }
    .foregroundStyle(.primary)
    .accessibilityIdentifier(A11y.NowPlaying.sleepTimer)
    .accessibilityLabel(sleepAccessibilityLabel)
    Spacer()
}
.frame(height: geometry.size.height * 0.06)
.padding(.horizontal, 32)
```

Matches the speed button's treatment exactly (padding 12/8, `Color.blue.opacity`,
corner radius 8, `.foregroundStyle(.primary)`) except the armed tint, which is
stronger so it reads as active in a dark room.

`.monospacedDigit()` is not cosmetic — without it the pill resizes as the
countdown ticks.

Helpers on the view:

```swift
@ObservedObject private var sleepTimer = SleepTimerManager.shared
@State private var showingSleepTimerPicker = false
@State private var countdownTick = Date()   // drives the 1Hz UI refresh

private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

private var sleepButtonLabel: String {
    SleepTimerManager.countdownText(
        for: sleepTimer.state, now: countdownTick,
        currentTime: audioPlayer.currentTime,
        currentChapter: audioPlayer.getCurrentChapter()
    ) ?? "Sleep"
}

private var sleepAccessibilityLabel: String {
    guard sleepTimer.isArmed else { return "Sleep timer, off" }
    // Spell it out - VoiceOver reading "12:45" as digits is unhelpful.
    ...  // "Sleep timer, 12 minutes 45 seconds remaining"
}
```

with `.onReceive(countdownTimer) { countdownTick = $0 }`.

This `Timer.publish` is a **display concern only** — matching the existing idiom
in `RestoreRequestsView.swift:79`. If it stalls, the UI label goes stale; the
actual pause is unaffected because it lives on the audio observer (spec §2).

### 6.3 The picker

**New file**: `ios/BookVault/Views/Components/SleepTimerPicker.swift` — same
directory and structure as `PlaybackSpeedPicker.swift`.

```swift
struct SleepTimerPicker: View {
    let currentState: SleepTimerState
    let hasChapters: Bool
    let onSelect: (SleepTimerMode) -> Void
    let onCancel: () -> Void
    let onExtend: () -> Void
}
```

Contents, top to bottom:

1. When armed — remaining time as a large `.monospacedDigit()` readout, plus an
   **Add 15 minutes** button
2. Preset rows: 8 / 15 / 30 / 45 / 60 / 90 minutes, checkmark on last-used
3. **End of chapter** row — `.disabled(!hasChapters)` with an explanatory footer
   when unavailable
4. **Turn off** row, only when armed

Presented `.presentationDetents([.height(480)])`, following the speed picker's
sheet pattern (`NowPlayingView.swift:262-271`) — sheet, not `Menu`, since there
is no `Menu` precedent in this codebase.

Wiring (after the speed sheet at `:271`):

```swift
.sheet(isPresented: $showingSleepTimerPicker) {
    SleepTimerPicker(
        currentState: sleepTimer.state,
        hasChapters: !audioPlayer.chapters.isEmpty,
        onSelect: { mode in
            sleepTimer.arm(mode)
            showingSleepTimerPicker = false
        },
        onCancel: {
            sleepTimer.cancel()
            audioPlayer.restoreVolumeAfterSleepFade()   // internal, not private
            showingSleepTimerPicker = false
        },
        onExtend: { sleepTimer.extend(by: 15 * 60) }
    )
    .presentationDetents([.height(480)])
}
```

Note `restoreVolumeAfterFade` needs `internal` (not `private`) access so cancel
from the UI can restore volume mid-fade. Alternative: have the observer notice
the `.off` transition and restore. The explicit call is clearer.

Add two `#Preview` blocks (off, armed), matching `PlaybackSpeedPicker.swift:145`.

### 6.4 Accessibility identifiers

Must land in **both** files in the same commit — `A11yIdentifierParityTests`
fails otherwise.

`Support/AccessibilityIdentifiers.swift:63-65`:

```swift
enum NowPlaying {
    static let root = "nowPlaying.root"
    static let sleepTimer = "nowPlaying.sleepTimer"
}
```

Mirror in `BookVaultUITests/A11yID.swift`.

---

## 7. Phase 7 — verification

### 7.1 UI tests

New `BookVaultUITests/SleepTimerUITests.swift`, following `MiniPlayerUITests.swift`:

```
sleepTimerButton_isVisibleOnNowPlaying
sleepTimerButton_opensPicker
selectingPreset_dismissesPickerAndShowsCountdown
turnOff_returnsButtonToIdleLabel
```

### 7.2 Gate

`npm run validate:ios` during development; **`npm run validate:full` before the
PR** (per CLAUDE.md §2 — `npm test` alone is not sufficient).

Watch specifically for: the a11y parity test, the coverage ratchet (four new
test files should push it up, not down), and SwiftLint on the new files.

### 7.3 Manual device pass — cannot be automated, must be a real device

The simulator cannot validate the core of this feature; backgrounding and lock
behavior differ. Required before merge:

1. **Arm 8 min, lock the device, let the screen sleep → audio pauses at 8 min.**
   This is the acceptance test for the whole feature.
2. Arm 8 min, background the app, return after 10 → paused, button idle.
3. Fade is audible; **next play is at full volume**.
4. Lock-screen transport controls still work while armed.
5. Lock-screen countdown appears and decrements ~1Hz. **Check on the smallest
   supported device** — if the book title truncates unusably, shorten the
   separator or drop the title while armed.
6. Countdown disappears from the lock screen after firing.
7. CarPlay Now Playing looks acceptable with the suffix (it shares
   `MPNowPlayingInfoCenter`, so it inherits the string whether or not we want it).
8. End-of-chapter fires at the boundary at 1.0× and at 1.5×.

Items 1 and 3 are the ones that would make the feature actively harmful if
broken — playing all night, or a permanently silent player.

---

## 8. Risks specific to implementation

| Risk                                                  | Mitigation                                                                         |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Volume stuck at 0 after an unexpected exit path       | `restoreVolumeAfterFade()` on fire/cancel/extend/new-book/stop; two explicit tests |
| Cover art at 0.35 looks cramped                       | §6.1 alternative: move the button to the toolbar                                   |
| Per-second Now Playing writes drain battery           | Album-key-only mutation, 1Hz rate limit, skipped when unchanged and when off       |
| Album `base` string drifts between the two call sites | Extract `albumBaseTitle` used by both (§5.4)                                       |
| Lock screen repaints slower than 1Hz                  | Accepted; countdown is a reassurance display, pause is independent                 |
| End-of-chapter fade too long at high speed            | 10s of _playback_ time = 20s wall-clock at 2×; acceptable, noted                   |
| A11y parity test fails                                | Both identifier files in the same commit                                           |

---

## 9. What could be cut

If this needs to be smaller, in order of what I'd drop first:

1. **Lock-screen countdown** (Phase 6) — the largest chunk of incidental
   complexity (rate limiting, string duplication, CarPlay bleed) for a
   reassurance display. The timer works identically without it.
2. **Fade-out** (part of Phase 3) — nice, and it carries the volume-restore risk.
   Without it, `.fire` just calls `pause()`.
3. **End-of-chapter** (Phase 4) — self-contained; presets alone are useful.

Phases 1, 2, 5 are the irreducible feature: arm a duration, see it count down,
have playback stop.
