# Wave: Hand-Gesture App for Mac — Implementation Plan

**Status:** Pre-development  
**Created:** 2026-11-23  
**Goal:** A lightweight macOS app that tracks your hands via webcam and enables gesture-based shortcuts, 3D playground, and optional features (face verification, media controls, meeting gestures, air drawing).

---

## Project Setup

### Environment
- **macOS:** 27.2 (27B52)
- **Xcode:** 27.2 (27B52, Apple Silicon), installed and selected
- **Swift:** 6.4
- **Dependencies:** None. Uses only built-in frameworks:
  - `AVFoundation` (camera)
  - `Vision` (hand tracking, face detection)
  - `SwiftUI` (UI)
  - `SceneKit` (3D playground)
  - `AppKit` (shortcuts, media keys, accessibility)

### Project Structure
```
wave/
├── Package.swift
├── Sources/Wave/
│   ├── WaveApp.swift           SwiftUI app, menu bar, tab view
│   ├── Core/
│   │   ├── HandTracker.swift      AVCaptureSession + Vision framework
│   │   ├── Gestures.swift         Pose detection rules (open, fist, pinch, V, counts)
│   │   ├── FaceCheck.swift        Face registration and matching
│   │   └── Output.swift           Send key presses, media keys, scroll, mouse
│   ├── Views/
│   │   ├── LearnView.swift        Gesture cards (emoji + "how to" + ✓)
│   │   ├── PlaygroundView.swift   SceneKit 3D scene
│   │   ├── ShortcutsView.swift    Copy/paste + finger macros
│   │   └── FeaturesView.swift     Feature toggles
│   ├── Features/
│   │   ├── MediaControls.swift    Play/pause, volume (if enabled)
│   │   ├── MeetingGestures.swift  Mute, raise hand, etc. (if enabled)
│   │   ├── AirInk.swift           Draw on screen (if enabled)
│   │   └── FaceTouchAlert.swift   Notify when hand touches face (if enabled)
│   └── Utils/
│       └── VisionHelpers.swift    Reusable Vision framework wrappers
└── PLAN.md (this file)
```

---

## Implementation Phases

### Phase 1: Core + UI Shell
**Goal:** Hand tracking works, gesture detection works, app runs.  
**Deliverable:** Tab view opens, camera shows joints, gestures are recognized.

**Files to create:**
1. **WaveApp.swift**
   - SwiftUI app with @main
   - Menu bar icon (NSStatusBar)
   - Tab view with four tabs: Learn, Playground, Shortcuts, Features
   - Window size: 800x600, resizable

2. **HandTracker.swift**
   - AVCaptureSession setup (front camera, 1280x720, ~30fps)
   - VNDetectHumanHandPoseRequest (max 2 hands)
   - VNDetectFaceRectanglesRequest (for face verification)
   - Delegate callback: emits `HandFrame` struct (array of hands, face bounds, timestamp)
   - Ask for camera permission on first launch

3. **Gestures.swift**
   - Pure functions: `HandFrame` → `Gesture` (enum)
   - Recognized gestures: `.open`, `.fist`, `.pinch`, `.peace`, `.point`, `.thumbsUp`, `.count(1...5)`, `.unknown`
   - Pose rules (all normalized by palm size, palm = wrist-to-middle-knuckle distance):
     - **Open:** all fingers extended (tip-to-wrist > 1.3×, all 5 fingers)
     - **Fist:** all fingers closed (tip-to-wrist < 0.5×, all 5 fingers)
     - **Pinch:** thumb + index close (< 0.4× palm), other fingers open
     - **Peace:** index + middle extended, others closed
     - **Point:** index extended, others closed
     - **Thumbs up:** thumb extended, others closed, thumb pointing up
     - **Count 1–5:** N fingers extended on that hand
   - Hysteresis: pinch uses on/off thresholds (0.25 close, 0.40 open) to prevent flicker
   - Stability: a pose must hold for 3 frames before it counts
   - Self-tests: `--selftest` flag with made-up hand points

4. **CameraOverlayView (SwiftUI)**
   - Draw camera frame using `AVCaptureVideoPreviewLayer` or manual rendering
   - Overlay hand joints as small circles
   - Show current recognized gesture + confidence
   - Used by Learn, Playground, and Features screens

5. **LearnView.swift**
   - 2×3 grid of cards (6 gestures per screen, paginated)
   - Card: emoji + "how to" text + current gesture match
   - Gesture matches → card highlights with ✓, then dims after 1s
   - Cards: open (👋), fist (✊), pinch (🤏), peace (✌️), point (☝️), thumbs up (👍), 1–5 (🖐️ variants)

6. **PlaygroundView.swift**
   - SceneKit scene on top of camera feed
   - Objects: one floating cube
   - Particles: sparkles follow fingertips (5 particles per frame)
   - Interaction:
     - Pinch on cube → grab (freeze position until release)
     - Drag while pinched → move with hand
     - Release → cube has velocity (direction + speed from hand motion)
     - Gravity always on
     - Fist gesture → shockwave (all objects pushed outward from screen center)
   - Camera: facing forward, so hand position maps 1:1 to screen space

7. **ShortcutsView.swift**
   - Copy/paste section:
     - Text box to test: "Fist then open = copy/paste"
     - Gesture state machine: fist for ≥0.5s then open within 2s = copy, then paste
   - Finger macros:
     - 5 dropdowns (hold 1–5 fingers for 0.5s), each runs a chosen Apple Shortcut
     - `shortcuts run <name>` via Process()
   - Clipboard history (memory only):
     - Pinch + hold → show strip of last 5 items
     - Swipe hand left/right to choose
     - Release → paste selected

8. **FeaturesView.swift**
   - Toggle switches (each controls one Feature file):
     - Face Verification (default: off)
     - Media Controls (default: off)
     - Meeting Gestures (default: off)
     - Air Ink (default: off)
     - Face-Touch Alert (default: off)
   - @AppStorage to persist on/off state

### Phase 2: Face Verification
**Goal:** Optional security layer.  
**Deliverable:** Register your face, gestures pause when you're not in frame.

**Files to create/modify:**
1. **FaceCheck.swift**
   - On first enable: show "Register my face" button
   - Tap → take 5 consecutive photos (countdown)
   - Store fingerprint using VNGenerateImageFeaturePrintRequest in Keychain
   - While running: crop face from frame, make fingerprint, compare with stored (Euclidean distance < threshold)
   - On match: green dot in top-right; on no match: grey dot
   - Gestures only work while green

2. **Modify HandTracker.swift**
   - Add face detection to the pipeline (already has `VNDetectFaceRectanglesRequest`)
   - Emit face bounds in `HandFrame`

### Phase 3: Optional Features (Phase 2 Completion)
Each feature is a separate file that runs only when its toggle is on.

1. **MediaControls.swift**
   - Fist → play/pause (NX_KEYTYPE_PLAY)
   - Pinch + drag up/down → volume up/down (NX_KEYTYPE_SOUND_UP/DOWN)
   - Requires Accessibility permission

2. **MeetingGestures.swift**
   - Finger on lips (index on mouth area) → mute toggle
   - Raise hand (hand raised above shoulder) → raise hand shortcut
   - Thumbs up → reaction shortcut (Zoom/Meet only)
   - Palm toward camera 1s → camera off
   - Requires Accessibility permission, needs app detection (which app is frontmost)

3. **AirInk.swift**
   - Pinch → start drawing glowing stroke
   - Drag → stroke follows index fingertip
   - Release/open palm → stop drawing
   - Stroke fades after 5s
   - Full-screen transparent window on top

4. **FaceTouchAlert.swift**
   - Face and hand bounding boxes detected
   - Overlap for 2s → notification ("Stop touching your face!")
   - Daily count in menu bar

### Phase 4: Testing & Polish
- Verify each gesture works with made-up data (Gestures.swift tests)
- Run on real hardware, adjust thresholds if needed
- Write README.md with feature descriptions and known limits

---

## Critical Design Decisions

1. **No third-party ML:** Use rule-based pose detection (simple geometry) instead of a trained classifier. It's fast, runs on-device without models, and works at any hand distance.

2. **Hand normalization:** All distances divided by palm size (wrist-to-middle-knuckle distance). This makes gestures work at any distance from the camera.

3. **Gesture stability:** Pose must hold for 3 frames before it counts, preventing jitter-caused false positives.

4. **Face verification:** Rough "is it you" check only, not cryptographically secure. Use Touch ID for real security.

5. **No depth:** Webcam depth is unreliable. All features use 2D hand position only.

6. **Accessibility permission required:** Needed to send key presses and media keys. Prompted on first launch.

---

## Known Limits & Trade-offs

| Limit | Why | When to Upgrade |
|-------|-----|-----------------|
| Single hand (some gestures) | Simpler detection, easier to reason about | If multi-hand gestures prove essential |
| 2D position only | Webcam depth is noisy | If depth matters (not in MVP) |
| Gesture set is fixed | Faster to ship, no ML training UI | If users request custom gestures |
| Face verification only on match | Less secure than biometric auth | If used for sensitive data |
| Air Ink strokes fade after 5s | Simple, no infinite-stroke rendering | If persistent drawing is needed |

---

## GitHub Repository

**Repo:** `srtkio/wave` (private)  
**Branch:** `main` (default)  
**Files:**
- Source files (all of the above)
- `.gitignore` (Xcode defaults)
- `README.md` (feature overview, usage, permissions, known limits)
- `PLAN.md` (this file)

---

## Verification Checklist

**Phase 1 (Core):**
- [ ] `swift build` succeeds
- [ ] App launches, menu bar icon appears
- [ ] Camera feed shows, hand joints visible
- [ ] Each Learn card lights up when gesture is made
- [ ] Playground: trails follow fingers, cube can be pinched and thrown, fist blasts
- [ ] Copy/paste: fist→open works, clipboard history shows up to 5 items
- [ ] Finger macros: holding 1–5 fingers runs a test Shortcut

**Phase 2 (Face):**
- [ ] Register face screen appears on first enable
- [ ] Gestures pause when you cover your face or leave frame
- [ ] Green/grey dot shows match status

**Phase 3 (Features):**
- [ ] Media controls toggle on/off: play/pause works, volume responds
- [ ] Meeting toggle on/off: finger-on-lips mutes, hand-raise works
- [ ] Air Ink toggle on/off: pinch draws, open palm clears
- [ ] Face-touch toggle on/off: touching face triggers notification

**Phase 4 (Polish):**
- [ ] README complete
- [ ] Repo public or private as intended
- [ ] `--selftest` passes
- [ ] Runs for 5 min without crashes or permission errors

---

## Timeline (Rough)
- **Day 1:** Phase 1 (Core) — 6–8 hours
- **Day 2:** Phase 2 (Face) + Phase 3 (Features) — 4–6 hours
- **Day 3:** Phase 4 (Testing, README) — 2–3 hours

**Total:** ~15 hours of focused work.

---

## Permissions Needed
1. **Camera** (Info.plist + prompt)
2. **Accessibility** (prompt on launch, can be granted/revoked in System Settings → Security & Privacy)

---

## Next Steps
1. ✅ Install Xcode 27.2 (build 27B52)
2. ✅ Create project folder and git repo
3. ✅ Write PLAN.md (this file)
4. ✅ Create GitHub repo `srtkio/wave`
5. ✅ Set active Xcode (`sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`)
6. ⬜ Create Package.swift and start Phase 1
