# Sleep Timer — Spec & Implementation Plan (iOS)

> **Status**: Proposed — not yet implemented
> **Platform**: iOS only. Deliberately excluded from web (see §9).
> **Reference behavior**: Audible's sleep timer.

---

## 1. Summary

Add a sleep timer to the iOS player so playback auto-pauses after a chosen
duration or at the end of the current chapter. A button on `NowPlayingView`
opens a picker; once armed, the button face shows a live countdown. Audio fades
out over the final seconds before pausing.

### In scope

- Fixed duration presets: **8, 15, 30, 45, 60, 90 minutes**
- **End of current chapter** option
- **Fade-out** over the last 10 seconds before the pause
- **Persisted last-used duration** so the picker pre-selects it
- Live countdown on the player button; cancel / extend while running
- **Remaining time visible on the lock screen** (see §3.4 for the constraint)

### Out of scope

- Shake-to-extend (explicitly deferred — needs motion handling, low value here)
- Web player (see §9)
- CarPlay surface (engine works if armed from the phone; no CarPlay button)
- Custom arbitrary durations (presets + end-of-chapter only, matching Audible)

---

## 2. Why not just use a `Timer`

This is the central design constraint and it drives the whole implementation.

A sleep timer runs for up to 90 minutes, in the background, with the screen
locked. In that state:

- `Timer` is scheduled on a RunLoop. When the app is suspended the RunLoop stops
  and **the timer does not fire**. The app is only kept alive here by the `audio`
  background mode, and iOS gives no guarantee that a RunLoop timer stays
  punctual across the whole window.
- Even while alive, `Timer` accumulates drift. Over 90 minutes that is
  user-visible.
- If the timer's callback is the _only_ thing that pauses playback, a missed fire
  means the book plays all night. That is the exact failure the feature exists to
  prevent.

**Design rule**: the source of truth is an absolute **deadline** (`Date`), never
a countdown integer.

- `SleepTimerManager` stores `fireDate: Date`.
- A 1-second `Timer` exists **only to drive the UI countdown**. It is a display
  concern.
- The authoritative check happens in `AudioPlayerManager`'s existing **0.5s
  periodic time observer** (`AudioPlayerManager.swift:899`), which is driven by
  `AVPlayer` and therefore ticks whenever audio is actually playing — including
  backgrounded and locked. If audio is playing, that observer is running; if
  audio is not playing, the timer has nothing to pause.

That single decision makes the feature robust without any background-task
gymnastics. `Date.now >= fireDate` is checked on every audio tick, so a late
check pauses late by at most 0.5s rather than never.

**End-of-chapter** uses the same observer but compares against
`currentChapter.endTime` instead of a wall-clock date, so it stays correct when
playback rate changes mid-run — a duration-based approximation would not.

---

## 3. User experience

### 3.1 The button

Lives in `NowPlayingView`, beside the existing speed button (`NowPlayingView.swift:209`),
and matches its visual treatment exactly — SF Symbol + label, horizontal padding
12 / vertical 8, `Color.blue.opacity(0.15)` background, corner radius 8.

| State                  | Icon            | Label                                 |
| ---------------------- | --------------- | ------------------------------------- |
| Idle                   | `moon.zzz`      | `Sleep`                               |
| Armed (duration)       | `moon.zzz.fill` | `12:45` — mm:ss, `.monospacedDigit()` |
| Armed (end of chapter) | `moon.zzz.fill` | `Chapter`                             |
| Fading out             | `moon.zzz.fill` | countdown continues, button tinted    |

Armed state uses a stronger tint (`Color.blue.opacity(0.30)`) so it reads as
active at a glance in a dark room.

### 3.2 The picker sheet

Follows the house pattern exactly — `@State` bool → `.sheet` → standalone view
with an `onSelect` callback, same as `PlaybackSpeedPicker`
(`NowPlayingView.swift:262`). No `Menu`; there is no `Menu` precedent in this
codebase.

Contents:

- Rows for each preset duration, checkmark on the last-used one
- **End of chapter** row, disabled with explanatory footer when `chapters.isEmpty`
- **Off** row, shown only while a timer is armed
- When armed, a header showing remaining time and an **Add 15 minutes** button

Presented with `.presentationDetents([.height(480)])`.

### 3.3 Behavior on fire

1. At `fireDate - 10s`, fade begins: volume ramps to 0 over 10 seconds.
2. At `fireDate`, `pause()` is called (existing method — it already saves
   progress and tears down the save timer).
3. **Volume is immediately restored** to its pre-fade value. This is critical:
   the fade is an effect, not a preference change. If the app crashed or was
   killed mid-fade, the next launch must not start silent.
4. Timer disarms itself; button returns to idle.
5. Full `updateNowPlayingInfo()` runs once, clearing the countdown from the
   lock-screen album line (§3.4).

### 3.4 Lock screen countdown

**Requirement**: remaining time must be visible on the lock screen, not just in
the app.

**Constraint**: `MPNowPlayingInfoCenter` has no "sleep timer" or auxiliary-text
property. The lock screen renders a fixed set of fields — title, album, artist,
artwork, scrubber. There is no supported way to add a custom line. Live
Activities are the only true "extra UI on the lock screen" mechanism, and they
are a much larger surface (widget extension, new target, `ActivityKit`
entitlement) than this feature warrants.

So the countdown has to ride along inside a field that already renders. The
options, and the tradeoff:

| Approach                                                    | Result                                   | Cost                                                          |
| ----------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------- |
| **Append to `MPMediaItemPropertyAlbumTitle`** ← recommended | Album line reads `Book Title · 💤 12:45` | Displaces part of the book/series title on the second line    |
| Append to `MPMediaItemPropertyTitle`                        | Countdown on the most prominent line     | Corrupts the chapter title, which is the primary label; worse |
| Live Activity                                               | A real, purpose-built countdown          | New target + entitlement + much larger scope                  |

**Recommendation**: append to the album line, only while a timer is armed. When
the timer is off, the field is byte-for-byte what it is today — this is a
strictly additive change with no idle-state regression.

Format: ` · 💤 12:45`, appended to the existing album string. The moon emoji
makes it self-describing without the word "sleep" eating horizontal space, which
matters because the album line truncates early on the lock screen.

**Refresh cadence — this is the important part.** `updateNowPlayingInfo()` is
currently called only on discrete events (resume, pause, seek, rate change,
chapter change). A countdown needs to tick. But rewriting the _entire_
`nowPlayingInfo` dictionary every second is wasteful — it re-runs the artwork
lookup and the chapter arithmetic 90 times per minute for a text change.

Therefore:

- Add a lightweight `updateNowPlayingSleepTimer()` that mutates **only** the
  album-title key on the existing `nowPlayingInfo` dictionary and writes it back.
  No artwork work, no chapter recomputation.
- Drive it from the 0.5s periodic time observer, but **rate-limited to once per
  second** and **only when the displayed mm:ss value actually changed**. At 0.5s
  ticks, half of all calls would otherwise be redundant writes.
- Only run at all when `sleepTimer.isArmed`.

When the timer disarms or fires, call the full `updateNowPlayingInfo()` once to
restore the clean album string.

**Caveat to verify on device**: iOS coalesces Now Playing updates, and the lock
screen may not repaint at a true 1Hz. The countdown should be treated as
approximate — it is a reassurance display, not a precision clock. The
authoritative pause still comes from the deadline check in §2, which is
completely independent of whether the lock screen repainted. This is worth
confirming in manual testing (§5) but is not a correctness risk.

### 3.5 Interaction with other controls

| Event                                 | Timer behavior                                                                                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| User pauses manually                  | Timer keeps running (Audible behavior — pausing to answer a question shouldn't cancel your sleep timer). Countdown continues against wall clock. |
| User plays a **different book**       | Timer cancels. Deliberate: `play(book:)` is a new listening session.                                                                             |
| Playback ends naturally               | Timer cancels.                                                                                                                                   |
| Call/interruption                     | Timer keeps running; existing interruption handling is untouched.                                                                                |
| User picks a new duration while armed | Replaces the deadline; fade state resets.                                                                                                        |

---

## 4. Components

### 4.1 New: `SleepTimerManager`

`ios/BookVault/Services/SleepTimerManager.swift`

`@MainActor final class SleepTimerManager: ObservableObject`, singleton +
testable init, matching `PlaybackSettings` / `ThemeManager` house style.

```swift
enum SleepTimerMode: Equatable {
    case duration(TimeInterval)
    case endOfChapter
}

enum SleepTimerState: Equatable {
    case off
    case armed(mode: SleepTimerMode, fireDate: Date?)  // nil fireDate == endOfChapter
    case fading(fireDate: Date)
}
```

Published: `state`, plus computed `remaining: TimeInterval?` and
`isArmed: Bool`.

Methods: `arm(_ mode:)`, `cancel()`, `extend(by:)`, and
`shouldFire(now:currentTime:currentChapter:) -> SleepTimerDecision`.

Plus a single formatting helper used by **both** the player button and the
lock-screen string, so the two can never disagree:

```swift
/// "12:45" for durations, "Chapter" for end-of-chapter, nil when off.
static func countdownText(for state: SleepTimerState, now: Date) -> String?
```

Also clock-injected, so it is unit-testable and produces identical output in
both surfaces.

That last method is the whole testable core: **pure, no side effects, no
`Date.now` read inside**. It takes the clock as a parameter, which means the
entire 90-minute behavior is unit-testable in microseconds without a real timer.
Returns `.none` / `.beginFade` / `.fire`.

Injecting the clock rather than reading it internally is what makes this
suite fast and deterministic; a manager that calls `Date()` internally would
force either sleeps or a mockable clock protocol threaded through everything.

### 4.2 Modified: `AudioPlayerManager`

- Hold a `sleepTimer: SleepTimerManager` reference (injected, defaulting to
  `.shared`, consistent with the existing DI init at `:149`).
- In the periodic time observer (`:899`), after the chapter-change block, call
  `sleepTimer.shouldFire(...)` and act on the decision.
- New private `applyFadeVolume(_:)` and `restoreVolumeAfterFade()`.
- Cancel the timer in `play(book:)` and `stop()`.
- New private `updateNowPlayingSleepTimer()` — the cheap album-line-only update
  described in §3.4. Also driven from the periodic observer, rate-limited to
  once per second via a stored `lastRenderedCountdown: String?`, which doubles
  as the changed-value check.
- `updateNowPlayingInfo()` gains a sleep-timer suffix on the album line so that
  full refreshes (chapter change, seek) don't transiently drop the countdown.
  This is the one edit to existing Now Playing logic; it is a no-op when the
  timer is off.

**Fade implementation**: ramp `player?.volume` directly, **not** the published
`volume` property. The `volume` property is bound to the Settings slider
(`NowPlayingView.swift:196`); driving it during a fade would make the slider
visibly crawl to zero and would persist a bogus value. Store
`preFadeVolume: Float?` privately and restore from it.

Fade steps are applied on the 0.5s observer tick — 20 steps over 10 seconds is
smooth enough for a volume ramp and avoids adding a second timer.

### 4.3 Modified: `AudioPlayerManaging` + `MockAudioPlayerManager`

Any protocol addition requires updating `MockAudioPlayerManager.swift` or the
mock-based suite stops compiling. Keep the protocol surface minimal — expose
only what views need. Views should observe `SleepTimerManager` directly rather
than proxying state through the player, which keeps the protocol change to
nothing at all if possible.

### 4.4 New: `SleepTimerPicker`

`ios/BookVault/Views/Components/SleepTimerPicker.swift` — mirrors
`PlaybackSpeedPicker`'s structure and file placement.

### 4.5 Modified: `PlaybackSettings`

Add `lastSleepTimerDuration: TimeInterval` with the same
`@Published` + `didSet` write-through + existence-check-and-clamp load pattern
already used for `defaultPlaybackRate` (`PlaybackSettings.swift:24-51`).
Key: `"lastSleepTimerDuration"`. Default: 30 minutes. Clamp to the preset set.

### 4.6 Modified: `NowPlayingView`

Add the button and sheet. **Note the layout constraint**: the view uses
`GeometryReader` fractions that already sum to ~0.98. The sleep button goes in
the **existing** speed/volume row (the `0.10` band) rather than adding a new
row, so no rebalancing is needed. Verify on the smallest supported device — the
row will hold two pill buttons plus the volume slider.

### 4.7 Accessibility

Add `A11y.NowPlaying.sleepTimerButton` to **both**
`Support/AccessibilityIdentifiers.swift` and `BookVaultUITests/A11yID.swift` —
`A11yIdentifierParityTests` enforces this and will fail otherwise.

The countdown label needs an `accessibilityLabel` that reads "Sleep timer, 12
minutes 45 seconds remaining" rather than letting VoiceOver read raw `12:45`.

---

## 5. Test plan

### Unit — `SleepTimerManagerRealTests.swift` (new)

Template: `ThemeManagerRealTests.swift` for the settings-store shape,
`AudioPlayerManagerRealTests.swift` for the engine shape.

Because `shouldFire` takes the clock as a parameter, all of these are instant:

- `arm(.duration)` sets a `fireDate` at now + interval
- `shouldFire` returns `.none` before deadline, `.beginFade` inside the fade
  window, `.fire` at/after deadline
- **Deadline in the past by 40 minutes → `.fire`** (the suspended-app case; this
  is the test that proves §2's design works)
- `endOfChapter` fires when `currentTime >= chapter.endTime`
- `endOfChapter` with no chapter → `.none`, never fires
- `extend(by:)` pushes the deadline and exits the fading state
- `cancel()` returns to `.off`
- Re-arming while armed replaces the deadline
- `countdownText` formats mm:ss with zero padding, returns `"Chapter"` for
  end-of-chapter and `nil` when off; clamps at `"0:00"` rather than going
  negative past the deadline

### Unit — `AudioPlayerManagerRealTests.swift` (extend)

Uses the existing `skipAudioSetup: true` init.

- Timer fire calls `pause()` and leaves `isPlaying == false`
- **Volume is restored to its pre-fade value after firing** — the regression
  guard for §3.3 step 3
- `play(book:)` with a different book cancels an armed timer
- Manual `pause()` does **not** cancel the timer

Now Playing (assert against `MPNowPlayingInfoCenter.default().nowPlayingInfo`,
which is readable in tests):

- Album line contains the countdown while armed
- Album line is unchanged from baseline when the timer is **off** — guards the
  "strictly additive" claim in §3.4
- Album line is cleaned up after the timer fires
- A full `updateNowPlayingInfo()` (e.g. chapter change) while armed **keeps** the
  countdown rather than dropping it

### Unit — `PlaybackSettings` (new file)

- Round-trips `lastSleepTimerDuration`; clamps out-of-range; defaults to 30m

### UI — `MiniPlayerUITests.swift` or a new `SleepTimerUITests.swift`

- Button visible on `NowPlayingView`, opens the sheet, selecting a preset
  dismisses it and the button shows a countdown

### Manual (cannot be automated — must be done on a real device)

1. Arm 8 minutes, lock the device, let the screen sleep. **Audio must pause at 8
   minutes.** This is the acceptance test for the whole feature.
2. Arm 8 minutes, background the app, return after 10 minutes — playback is
   paused, button is idle.
3. Verify the fade is audible and the next play is at full volume.
4. Verify the lock-screen controls still work while a timer is armed.
5. **Lock-screen countdown**: confirm it appears, decrements roughly once per
   second, and is legible without truncating the book title beyond usefulness.
   Check on the smallest supported device, where the album line truncates
   soonest — if the title is unreadable there, fall back to a shorter separator
   or drop the book title while armed.
6. Confirm the countdown disappears from the lock screen after the timer fires.
7. Check the countdown on CarPlay's Now Playing template — it reads the same
   `MPNowPlayingInfoCenter`, so it will inherit the album-line suffix. Verify it
   looks acceptable there rather than broken.

---

## 6. Implementation phases

| Phase | Work                                                                                      | Verify                                    |
| ----- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **1** | `SleepTimerManager` + `SleepTimerMode/State` + unit tests                                 | Tests pass; no UI yet                     |
| **2** | `PlaybackSettings.lastSleepTimerDuration` + tests                                         | Round-trip test                           |
| **3** | Wire into `AudioPlayerManager` observer; fade + volume restore; engine tests              | Duration timer pauses audio in-app        |
| **4** | End-of-chapter mode                                                                       | Fires at chapter boundary                 |
| **5** | `SleepTimerPicker` + `NowPlayingView` button + countdown + a11y IDs                       | Full flow in simulator                    |
| **6** | Lock-screen countdown: `updateNowPlayingSleepTimer()` + rate limiting + Now Playing tests | Countdown visible on lock screen          |
| **7** | UI tests, then the §5 manual device checks                                                | Locked-device pause + countdown confirmed |

Phases 1–2 are pure model work with no UI dependency and can land independently.

---

## 7. Risks

| Risk                                                  | Mitigation                                                                                                           |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Timer doesn't fire when backgrounded                  | Deadline-based checking on the AVPlayer time observer (§2) — the core design                                         |
| Fade leaves volume at 0 permanently                   | Restore from `preFadeVolume` on every exit path; explicit regression test                                            |
| Slider visibly moves during fade                      | Ramp `player.volume`, not the published `volume`                                                                     |
| `MockAudioPlayerManager` breaks the build             | Keep protocol unchanged if possible; views observe `SleepTimerManager` directly                                      |
| A11y parity test fails                                | Add the identifier to both lists in the same commit                                                                  |
| Chapter-relative vs absolute time confusion           | End-of-chapter compares absolute `currentTime` to absolute `chapter.endTime`; both are absolute in this codebase     |
| Countdown truncates the book title on the lock screen | Short ` · 💤 mm:ss` suffix; verify on the smallest device (§5.5) and shorten if needed                               |
| Per-second Now Playing writes cost battery            | Album-key-only mutation, rate-limited to 1Hz, skipped when the rendered value is unchanged and when the timer is off |
| Lock screen repaints slower than 1Hz                  | Accepted — the countdown is a reassurance display; the authoritative pause is independent of it (§3.4)               |
| CarPlay inherits the suffix unintentionally           | Shares `MPNowPlayingInfoCenter` by design; verify visually (§5.7)                                                    |

---

## 8. Open questions

1. **Should the timer survive an app relaunch?** Current spec says no — an armed
   timer dies with the process. Persisting the deadline would let a timer fire
   after a crash-and-reopen, but playback wouldn't be running anyway, so there is
   nothing to pause. Recommend leaving it out.
2. **Should there be a Settings row for a default sleep duration**, parallel to
   default playback speed? Not in this spec; the last-used value already covers
   the common case.
3. **Is the album-line countdown good enough, or is a Live Activity wanted?**
   §3.4 recommends the album line because it is additive and cheap. A Live
   Activity would give a proper countdown on the lock screen and Dynamic Island,
   but needs a widget extension, a new build target, and `ActivityKit` work —
   realistically larger than the rest of this feature combined. Recommend
   shipping the album line first and revisiting only if it reads poorly on
   device (§5.5). The two are not mutually exclusive.

---

## 9. Why web is excluded

The web player (`components/AudioPlayer.tsx`) is a fixed bottom bar with no
full-screen view and no state store. More decisively: browsers throttle timers in
backgrounded tabs and may suspend the tab entirely — the same failure mode as
§2, but without an equivalent of the AVPlayer time observer to fall back on, and
without a background audio mode guaranteeing the page stays alive. A sleep timer
is used almost exclusively while falling asleep with the screen off, which is not
a web session. Revisit only if the web player gains a real playback store.
