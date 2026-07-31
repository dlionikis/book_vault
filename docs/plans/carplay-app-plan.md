# CarPlay App — Requirements

> **Created**: July 25, 2026
> **Status**: ⏸️ **Implemented, blocked on the Apple entitlement.** Browse, playback
> and Now Playing all ship; see [carplay-implementation-plan.md](carplay-implementation-plan.md)
> for what remains (A0 entitlement request, A4 wiring, C4/C5 device passes).
> **Priority**: TBD
> **Platform**: iOS only

> **Note**: The open questions below have since been answered by a codebase
> investigation. See §1 of the [implementation plan](carplay-implementation-plan.md)
> for the findings and resolutions — notably that the Series View Toggle work has
> landed (Q2), a download/offline feature does exist (Q3), and chapter loading
> needs a player-level refactor before CarPlay can show chapter controls (Q4).

---

## Background

A prior investigation (July 2026) confirmed **zero existing CarPlay support**:

- No `CarPlay`, `CPTemplateApplicationScene`, or `CPInterfaceController` references anywhere in `ios/`.
- No CarPlay entitlement (`com.apple.developer.carplay-audio`) in `ios/BookVault/BookVault.entitlements`.
- No CarPlay scene configuration in `Info.plist` (`UIApplicationSupportsMultipleScenes` is `false`, no scene delegate for CarPlay).
- This is a from-scratch build requiring an Apple CarPlay entitlement request (Apple requires explicit approval for CarPlay audio apps, which can take time — should be requested early, independent of dev timeline).

**Good news** — the audio playback foundation CarPlay needs already exists and is solid:

- `AudioPlayerManager.swift` already wires up `MPRemoteCommandCenter` (play/pause/skip commands).
- `updateNowPlayingInfo()` already populates `MPNowPlayingInfoCenter` (title/artist/artwork/elapsed/duration/rate) from ~8 call sites across playback state changes.
- `Info.plist` already declares `UIBackgroundModes: audio`.
- This means CarPlay work is primarily **"add a CarPlay scene + build template UI that calls into the existing `AudioPlayerManager.shared`,"** not rebuilding playback from scratch.

## Decided Scope: Browse + Play Only (v1)

Per discussion, v1 is intentionally constrained to match Apple's CarPlay audio app guidelines for a first release:

- Browse library / series and select something to play.
- Now Playing screen with standard transport controls (play/pause, skip forward/back, chapter navigation if applicable).
- **Explicitly not in v1**: search from the car, list management (add/remove from library), download management, account/settings screens.

## Proposed Scope Detail

1. **CarPlay scene & entitlement**
   - Request CarPlay audio entitlement from Apple (separate process, start early — this can be a lead-time bottleneck independent of code).
   - Add `CPTemplateApplicationSceneDelegate` + scene manifest entry in `Info.plist`.

2. **Browse templates** (`CPListTemplate` — CarPlay's UIKit-free template system, not SwiftUI)
   - Top-level list: likely Library and/or Series (mirrors the iOS app's own top-level browse, pending the Series View Toggle work above — worth sequencing after or alongside that, since CarPlay's list structure should mirror whatever Catalog/Library/Series navigation model lands there).
   - Drill into a series → list of books → select to play.
   - Cover art thumbnails in list rows (CarPlay supports this via `CPListItem` images).

3. **Now Playing template** (`CPNowPlayingTemplate`)
   - Reuses existing `AudioPlayerManager.shared` state — no new playback logic, just template bindings.
   - Transport controls: play/pause, skip back/forward (existing `MPRemoteCommandCenter` handlers), chapter skip if the existing chapter model supports it (chapters are lazy-loaded per `CLAUDE.md` — need to confirm chapter data is available/loaded before CarPlay needs to display it).

4. **Auth handling in CarPlay context**
   - CarPlay scene launches independently of the phone UI being open — need to confirm behavior if the user isn't logged in (show a "open the app on your phone to sign in" message in CarPlay, since CarPlay templates can't host a full login form).

## Open Questions

1. **Entitlement lead time**: Has the Apple CarPlay entitlement request been submitted yet? If not, this should likely be kicked off immediately, in parallel with everything else, since Apple's review/approval process is the longest pole regardless of when coding starts.
2. **Relationship to Series View Toggle work**: Should CarPlay's browse structure be built against the _current_ flat Catalog/Library, or wait until the Series toggle work (above) lands so CarPlay's list hierarchy matches the phone app's final navigation model? Building CarPlay first risks rework; waiting delays CarPlay.
3. **Offline/downloaded content**: Does v1 CarPlay only stream (same as phone today), or does it need to account for any offline/downloaded playback path? (Need to confirm whether Book Vault iOS has a download-for-offline feature at all — not confirmed in the investigation.)
4. **Chapter navigation**: Chapters are lazy-loaded on first playback per project docs — does CarPlay's Now Playing template need chapter data pre-fetched before the scene can display chapter skip controls, and what's the UX if chapters haven't loaded yet?
5. **Testing**: CarPlay can only be fully tested via the CarPlay Simulator (bundled with Xcode) or a real head unit/dock. Should be called out as a testing-approach decision before implementation — this is a different QA loop than the existing simulator-based iOS test flow.
6. **Auth/session behavior in CarPlay**: If the [iOS logout/session bug](../archive/completed-plans/ios-audio-session-persistence-plan.md) reproduces while CarPlay is connected, what should CarPlay show? Worth sequencing CarPlay after that bug is resolved, since a mid-drive forced logout with no way to re-auth from CarPlay would be a bad experience.

## Explicitly Out of Scope (per this request, v1)

- Search from CarPlay.
- Adding/removing books or series to/from library from CarPlay.
- Download/offline management from CarPlay.
- Account settings / login form inside CarPlay.

## Acceptance Criteria

Superseded by §7 of the [implementation plan](carplay-implementation-plan.md),
which tracks these against actual tasks. Status as of July 31, 2026:

- [ ] Apple CarPlay entitlement obtained and provisioning updated — **not submitted (A0)**.
- [x] CarPlay scene launches and shows a browsable list — tab bar with Library, Series, Downloaded (A2, B3–B6).
- [x] Selecting a book starts playback via existing `AudioPlayerManager` (B3, B7).
- [x] Transport controls work from the CarPlay UI, including chapter navigation when chapters exist (B7). **Phone↔CarPlay sync is by construction** — both drive the same singletons — but is unverified without a live connection.
- [x] Logged-out state shows a clear message, and session restore does not flash a false logged-out state (C1).
- [ ] Manual pass on CarPlay Simulator — **not done (C4)**; nothing here has run against a live CarPlay connection.
