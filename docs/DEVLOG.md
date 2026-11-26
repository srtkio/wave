# Wave dev log

Every problem we hit, what caused it, and what we did. Newest first. Kept up to date as work happens.

Raw evidence for a test session lives in `~/Library/Logs/Wave/session.log` (menu bar → **Show test log**): what Wave saw (gestures, hands kept or ignored with their palm sizes, signs) and did (cursor events, notch messages). Text only, no images.

## Open

| # | Problem | Status |
|---|---|---|
| 8b | Face check is a convenience, not identity: Vision feature prints are general image embeddings (pose, light and background matter). Real recognition needs a face-embedding Core ML model (ArcFace/MobileFaceNet style) plus liveness | planned (step 4) |

## Fixed

### 2026-11-27: Made the repo public
- **Before publishing:**
  - Scanned the full history for keys, tokens and private keys: none.
  - Removed another person's name and email from this dev log in every commit (history rewritten with plumbing, code unchanged, 36/36 commits still authored by srtkio).
- **Published as a fresh repo:** the clean history went to a new public `srtkio/wave`, and the old private repo was renamed `srtkio/wave-archive`. GitHub keeps unreachable old commits viewable by ID, so flipping the old repo to public would have exposed them.

### 2026-11-25: Cursor needed big hand movements and felt choppy
- **Seen (user):** "you need to move your hand a lot". The user asked for smoother motion and a higher "DPI".
- **Cause:**
  - The cursor was the knuckle's *position* inside the middle 60% of the camera frame, stretched to the screen. Crossing the screen took about 4 palm-widths of hand travel.
  - Stretching that position also stretched camera jitter.
  - The pointer moved only when a camera frame arrived (30 Hz), so it stepped.
- **Fix:**
  - **Trackpad-style motion:** the knuckle's *motion* in palm-widths moves the cursor, with acceleration: 0.35 screen/palm slow (~6 px/mm), +0.5 per palm/s, max 2.0. It's the same near or far from the camera. Under 0.06 palm/s counts as stillness, so a resting hand doesn't drift.
  - **Smoothing:** stronger filtering at rest (One Euro min cutoff 1.0 → 0.6 Hz), and the pointer glides toward each new position at 120 Hz. Clicks snap to the aimed point first.
  - **Start:** cursor mode picks up wherever the pointer already is.
  - **Speed slider** on the Cursor page (0.5–2.5).
  - Losing the hand resets motion, so the cursor doesn't jump when the hand comes back elsewhere.
- **Check:** self-test `info cursor:` line. A ½-palm (~4 cm) slide moves 0.24 screen slowly and 0.52 fast, and 0.24 from twice as far away. Tests: still hand doesn't drift; fast ≥ 2× slow; distance-independent.

### 2026-11-25: ✌️ screenshot opened the selection tool
- **Seen (user):** wanted a whole-screen shot saved where screenshots normally go.
- **Fix:** ✌️ now sends ⌘⇧3 (full screen, saved to the location set in the Screenshot app). The notch ring tucks away first (0.45s) so it's not in the shot, and the confirmation shows afterwards.

### 2026-11-25: UI looked like "AI slop"; whole window was camera; menu dropdown was a mess
- **Seen:**
  - The blue→violet gradient glass, forced dark mode and a full-window camera with every control on top of it.
  - The menu dropdown had misaligned insets, a gradient icon, "Thum…" truncation, L as a boxed letter (🇱), pickers with no affordance, no hover, and it was too tall.
- **Fix:** native macOS UI that follows the system light/dark theme and accent colour.
  - A `NavigationSplitView` sidebar: Home · Cursor · Hand Signs · Features · Learn · Playground · Log.
  - Home has a 480pt camera card with a fullscreen button (Esc returns), "What Wave sees", the Wave switch, a permissions checklist (re-checked every 2s, never prompts) and recent activity.
  - The menu dropdown is a compact 280pt Control-Center-style panel: switch, status, Hand signs switch, Open / Show Log / Quit rows with hover. Sign pickers moved to the window.
  - The notch pill is pure black and white.
  - The icon is a white hand on solid blue.
  - L is shown as a plain "L".
  - Removed the old Shortcuts tab and its engine (replaced by hand signs).
- **Also:** face dots now show whenever a camera view is on screen (the face pass used to run only while a face feature was on).

### 2026-11-25: App crashed on launch after the UI rework
- **Cause:** removing `NSApp.appearance = darkAqua` meant nothing created `NSApplication.shared` before `NSApp.setActivationPolicy`, so `NSApp` was nil.
- **Fix:** call `NSApplication.shared.setActivationPolicy(.regular)`. Found by launching the installed app during the rework.

### 2026-11-25: Commits were linked to the wrong GitHub account
- **Seen:** GitHub showed another person's GitHub account as the author on every commit.
- **Cause:** when the repo was created (2026-11-23), its local git config was set to an email taken from the Claude account's context, which belongs to someone else, instead of leaving the Mac's identity, `Sarthak Rai <trojan5779@gmail.com>` (srtkio). GitHub links commits to accounts by email.
- **Fix:**
  - Removed the repo-local `user.email`/`user.name`.
  - Re-created all 33 commits with srtkio as author and committer. Trees, messages, dates and Claude co-author lines were unchanged; this was checked commit by commit.
  - Force-pushed `main` and `build-mvp`. GitHub API: 33/33 commits now `author.login = srtkio`.
  - The stale branch `worktree-airhand-setup` (5 old commits) must be deleted on GitHub.
- **Visibility:** the repo is private and srtkio is the only collaborator, so the other account could never open it or its commits. Commits to a private repo you can't access don't appear on your contribution graph, and no notifications are sent for authored commits.
- **Rule:** never set a repo-local git identity. Check `git log --format='%an <%ae>'` before the first push.

### 2026-11-25: Features cross-fired
- **Seen or found in review:**
  - 👌 armed cursor mode at 0.6s and fired copy at 0.8s.
  - Air ink and cursor arming both used pinch.
  - Pointing at your lips drew ink and muted the meeting at once.
  - A fist on your chin fired media and the face-touch alert.
  - Closing your hand on the way to 👍 played/paused, then 👍 toggled it back.
- **Fix:** one rule decides who owns the hand, in `Features/Arbiter.swift`:
  1. Face check failing → nobody acts.
  2. Cursor mode active or arming → only cursor.
  3. A bound sign pose → only hand signs (unless air ink is mid-stroke).
  4. Otherwise features, split by where the hand is: index on lips → meeting mute; hand on face → face-touch alert; elsewhere → media (fist held 0.4s) and air ink (now **point** to draw, open palm clears).
  - Cursor arming ignores the 👌 pose.
  - Lane changes go to the session log (`arbiter lane …`).
- **Check:** `arbiter crossfire matrix` self-test, 10 poses × 5 states, at most one system acting in every cell.
- **Watch for:** a casual pinch with the other three fingers loosely open won't arm cursor mode, so curl one. A point with the thumb out is the L sign (paste), so tuck the thumb to draw.

### 2026-11-25: Face check reworked and debuggable
- **Before:** 5 raw crops, a guessed threshold, and no visibility into why it matched or not.
- **Now:**
  - Landmarks (`VNDetectFaceLandmarksRequest`, 10 Hz, largest face) are drawn as dots.
  - The crop is a square around the landmarks, levelled by the eye-line roll, grayscale, 224×224 and normalised.
  - Registration takes 8 samples (straight / left / right / up) and rejects frames with zero or several faces.
  - Threshold = your own max spread × 1.3 + 0.1.
  - Unlocks on the first match and locks after 2 misses.
  - Every check is logged: `face check: nearest=… threshold=… -> match/no match`.
- **Note:** old registrations aren't loaded, so register again (new file `face2.prints`).
- **Check:** `face check maths` self-test (threshold, hysteresis, crop geometry, roll; a flipped roll sign fails it).

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
