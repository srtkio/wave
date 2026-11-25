# Changelog

## Unreleased

- Test log: while Wave is on it writes what it sees and does (gestures, hands kept or ignored, signs, cursor events, notch messages) to `~/Library/Logs/Wave/session.log`. Text only, no images. Open it from the menu bar with **Show test log**.
- Mission Control sign now opens Mission Control directly, so it works whatever your keyboard shortcut is.
- Media controls: removed pinch-and-slide volume, which clashed with the cursor-mode pinch. Put volume up/down on a hand sign instead.

## v0.2 (2026-11-25): menu-bar redesign

- Wave is now a menu-bar app: no Dock icon and no window at launch. The dropdown has the Wave on/off switch (the camera only runs while on), a status line, the Hand signs section, "Open Wave window…" and Quit.
- Notch HUD: a black pill that grows out of the notch to show flashes, sticky modes and a progress ring for holds.
- Closest-hand filter: only the closest hand counts; far-away hands (people behind you) are ignored.
- Cursor mode: pinch-hold 0.6 s to start; index knuckle moves the cursor; tap, double tap and thumb+middle tap click; pinch-hold drags; peace sign scrolls; both hands pinching for 2 s exits.
- Hand signs, held 0.8 s: thumbs up play/pause, rock next track, call me Mission Control, peace screenshot, OK copy, L paste. Each can be reassigned in the menu bar, including to any Apple Shortcut.
- The old always-on gesture shortcuts (grab and drop, finger macros, clipboard history) are off by default; other gesture features pause while cursor mode is on.
- `--snapshot` also renders the menu panel and the notch pill states.
- Docs: README rewrite, docs/GESTURES.md, updated PLAN.md and CORE_API.md.

## v0.1 (2026-11-24): first window MVP

- Window app with Learn, Playground, Shortcuts and Features tabs over a shared camera stage.
- Hand tracking with Apple Vision, gesture rules (open, fist, pinch, peace, point, thumbs up, finger counts).
- Playground 3D scene, copy/paste and finger-count shortcuts, clipboard history.
- Optional features: face check, media controls, meeting mute, air ink, face-touch alert.
- Generated app icon, `--selftest` and `--snapshot` dev modes.
