# Wave dev log

Every problem we hit, what caused it, and what we did. Newest first. Kept up to date as work happens.

Raw evidence for a test session lives in `~/Library/Logs/Wave/session.log` (menu bar → **Show test log**): what Wave saw (gestures, hands kept or ignored with their palm sizes, signs) and did (cursor events, notch messages). Text only, no images.

## Open

| # | Problem | Status |
|---|---|---|
| 9 | Features could cross-fire (fist used by both media play/pause and old grab/drop; pinch used by air ink and cursor arming) | in progress |
| 8 | Face check unreliable; no face dots; no way to see why it matched or not | in progress |
| 7 | UI: whole window is camera, everything on one screen, gradient "glow" look | in progress |

## Fixed

### 2026-11-25: Accessibility popup kept coming back; cursor didn't move
- **Seen:** "Wave.app would like to control this Mac" on every launch. Session log showed cursor mode working (`cursor enter`, `leftDown`, `leftClick(1)`, `rightClick`) but every enter also flashed `Allow Accessibility`, so no mouse events were posted.
- **Cause:** `build.sh` signed ad hoc (`codesign -s -`). The designated requirement was `cdhash H"…"`, which changes on every build, so macOS treated each build as a new app and dropped the grant. Every feature also called the prompting API on its own, so the popup repeated.
- **Fix:** sign with a fixed local identity, "Wave Local Signing" (`scripts/make-signing-identity.sh`, one-time). The requirement is now `identifier "com.srtkio.wave" and certificate leaf = H"28e0…"`, the same across rebuilds. `Output.ensureAccessibility()` shows the system prompt at most once per launch. Stale entries cleared with `tccutil reset Accessibility com.srtkio.wave`.
- **After this:** grant Accessibility once to `/Applications/Wave.app`.

### 2026-11-25: Notch flashed every gesture
- **Seen:** 26 notch messages in about 2 minutes of testing ("Point", "Pinch", …).
- **Fix:** the notch shows only things Wave did (cursor on/off, sign fired, …); recognised gestures go to the session log instead.

### 2026-11-25: App "not opening"
- **Seen:** double-clicking did nothing visible.
- **Cause:** it was a menu-bar-only app (`LSUIElement`, `.accessory`), and the icon was hidden behind the notch because the menu bar was full.
- **Fix:** normal app: Dock icon, window at launch, installed to `/Applications` by `build.sh`.

### 2026-11-25: Media pinch-volume clashed with cursor arming
- **Cause:** both used a held thumb+index pinch.
- **Fix:** removed pinch-volume; volume is a hand-sign action.

### 2026-11-25: Mission Control sign did nothing (expected)
- **Cause:** a posted Ctrl+↑ depends on the user's shortcut settings and fn flags.
- **Fix:** open `/System/Applications/Mission Control.app` directly.

### 2026-11-25: 👌 counted as a pinch
- **Cause:** `classify()` checked thumb–index distance before looking at the other fingers.
- **Fix:** a pinch now needs middle/ring/little not all extended. Self-test `ok is not pinch`.

### 2026-11-25: Window app misfired when people behind were moving
- **Cause:** every detected hand counted.
- **Fix:** `primaryHands()` drops hands with palm size under 0.08 of the frame and sorts the closest first. First test log: the user's hand measured 0.16–0.33, people behind 0.010–0.026, so the cut-off has wide margins.

### 2026-11-24: Sub-agents couldn't write to their own worktrees
- **Cause:** a session isolated to one worktree can't enter another.
- **Fix:** agents share one worktree with disjoint file ownership, and the main session commits.

### 2026-11-24: Clipboard history could keep passwords (security review)
- **Fix:** skip pasteboard items marked concealed, transient or auto-generated; record only while the feature is on.

### 2026-11-23: Xcode install "succeeded" but wasn't installed
- **Cause:** `xcodes` exited 0 after `Missing username or a password`.
- **Fix:** the user installed Xcode from the App Store, then ran `xcode-select -s`. Lesson: check results, not exit codes.
