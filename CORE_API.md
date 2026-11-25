# Wave Core API

Everything in `Sources/Wave/Core/`, plus the cursor and hand-sign engines from `Sources/Wave/Features/`. Tab authors build on this and do not change it.

## Coordinates
Every point and rect is **normalised 0–1, origin top-left, mirrored like a selfie**, so it matches the preview. Draw with `viewPoint(p, in: size)`.

The one exception is `frame.pixelBuffer`. It is the **raw, unmirrored** sensor image in Vision space, with the origin at bottom-left. To crop the face from it, convert `f = frame.face` back with `CGRect(x: 1 - f.maxX, y: 1 - f.maxY, width: f.width, height: f.height)`. The same formula converts in both directions. You can use the result directly as a Vision `regionOfInterest`, or multiply it by the pixel size to get a CIImage crop.

## HandTypes.swift
| API | Example |
|---|---|
| `typealias Joint = VNHumanHandPoseObservation.JointName` | `hand.points[.indexTip]` |
| `struct Hand { var points: [Joint: CGPoint]; var chirality: VNChirality }`. Only joints with confidence > 0.3 are included, so always unwrap. | `if let tip = hand.points[.indexTip] { … }` |
| `struct HandFrame { var hands: [Hand]; var face: CGRect?; var pixelBuffer: CVPixelBuffer?; var time: TimeInterval }` | `frame.hands.first` |
| `func viewPoint(_ p: CGPoint, in size: CGSize) -> CGPoint` maps a point onto a view showing the 16:9 camera with aspect fill. | `.position(viewPoint(tip, in: size))` |

## Gestures.swift (pure logic)
| API | Example |
|---|---|
| `enum Gesture: String, CaseIterable { case none, open, fist, pinch, peace, point, thumbsUp }` | `Gesture.allCases` |
| `func extendedFingers(_ h: Hand) -> [Bool]` returns [thumb, index, middle, ring, little]. | `extendedFingers(h)[1]` is true when the index is up |
| `func fingerCount(_ h: Hand) -> Int` counts 0–5, thumb included. | `fingerCount(h) == 3` |
| `func classify(_ h: Hand) -> Gesture` gives the raw per-frame gesture, without stabilising. | `classify(h) == .pinch` |
| `struct GestureStabilizer { mutating func update(_ g: Gesture) -> Gesture }` switches only after 3 identical frames in a row. | `stable = stab.update(classify(h))` |

`classify` checks these rules in order. All distances are relative to palm size, which is wrist to middle MCP.
1. A key joint is missing: `none`.
2. Thumb tip is within 0.3 of the index tip: `pinch`.
3. All four fingers are extended: `open`.
4. No fingers are extended: `thumbsUp` if the thumb is extended and above the index MCP, otherwise `fist`.
5. Only the index is extended: `point`.
6. Only index and middle are extended: `peace`.
7. Anything else: `none`.

For `point` and `peace` the thumb is ignored. A finger counts as extended when tip-to-wrist is more than 1.1 × PIP-to-wrist. The thumb counts as extended when thumbTip-to-indexMCP is more than 0.5 × palm.

## HandTracker.swift
`HandTracker.shared` is `@Observable`. Read it directly in a SwiftUI `body` and the view updates.
| API | Example |
|---|---|
| `var frame: HandFrame` holds the latest frame and is updated every frame. | `HandTracker.shared.frame.hands.count` |
| `var gesture: Gesture` is the stable gesture of the first hand, or `.none` when there is no hand. | `if t.gesture == .fist { … }` |
| `var fingers: Int` is the finger count of the first hand. | `Text("\(t.fingers)")` |
| `var handVisible: Bool` is true while at least one hand is in frame. It only changes on transitions, so it is cheap to observe. | `if t.handVisible { … }` |
| `var authorized: Bool?` is nil before asking, false if denied, true once the camera is running. | `if t.authorized == false { … }` |
| `var running: Bool` is true while Wave is on (camera running). Set it with `start()` and `stop()`. | `if t.running { … }` |
| `var cursorActive: Bool` is true while cursor mode owns the hand. Other gesture features must stay quiet. | `guard !t.cursorActive else { return }` |
| `var detectFaces: Bool` (default false). Set it to true to fill `frame.face`. | `HandTracker.shared.detectFaces = true` |
| `var gesturesAllowed: Bool` (default true). The face check sets it to false to block gestures. | `guard t.gesturesAllowed else { return }` |
| `func stop()` turns Wave off: stops the camera, ends cursor mode, clears the seen hands. | `HandTracker.shared.stop()` |
| `let session: AVCaptureSession` | used by `CameraPreview` |
| `func start()` turns Wave on: shows "Wave on" in the notch, asks for camera access and starts capture. It is safe to call more than once. The menu bar switch and the window call it. | `HandTracker.shared.start()` |
| `@discardableResult func onFrame(_ f: @escaping (HandFrame, Gesture) -> Void) -> UUID` runs on main every frame, but **only while `gesturesAllowed`**. | `id = t.onFrame { frame, g in … }` |
| `@discardableResult func onAnyFrame(_ f: @escaping (HandFrame, Gesture) -> Void) -> UUID` runs on main every frame, always. It exists for the face check. | `id = t.onAnyFrame { frame, _ in … }` |
| `func removeListener(_ id: UUID)` removes a listener registered with either call. | `t.removeListener(id)` |

### Closest hand
`primaryHands(_:)` (bottom of HandTracker.swift) drops hands whose `palmSize` is under `minPalmSize` (0.08 of the frame) and sorts the rest closest first. The tracker applies it before anything else, so `frame.hands.first` is always the closest hand.

## Signs.swift (pure logic)
| API | Example |
|---|---|
| `enum Sign { case rock, callMe, ok, l, thumbsUp, peace }` with `emoji` and `title`. | `Sign.ok.emoji` |
| `func sign(_ h: Hand) -> Sign?` is the sign the hand is making, or nil. Palm-relative like `classify`. A plain pinch is not a sign. | `sign(hand) == .l` |

## NotchHUD.swift
`NotchHUD.shared` is `@Observable`. It owns the black pill under the notch, created lazily.
| API | Example |
|---|---|
| `flash(_ text:, symbol:, seconds: 1.4)` shows something briefly. | `NotchHUD.shared.flash("Copied", symbol: "doc.on.doc")` |
| `setSticky(_ text: String?, symbol:)` stays until set to nil (used for "Cursor"). | `NotchHUD.shared.setSticky(nil)` |
| `progress: Double?` shows a ring on the right for 0...1, nil hides it. | `NotchHUD.shared.progress = 0.4` |
| `NotchPill(notch:hud:)` is the view, and `headless` skips the real panel. Both exist so `--snapshot` can render it. | |

## CursorMode.swift and CursorCore.swift
`CursorCore` is a pure state machine: `step(t:hands:) -> [CursorEvent]` (move, leftDown/Up, leftClick(n), rightClick, scroll, scrollMode, enter, exit, progress). All thresholds are static lets on it. `CursorMode.shared` feeds it from `onAnyFrame`, posts CGEvents, sets `HandTracker.cursorActive` and drives the notch. `CursorMode.shared.stop()` ends it at once (called by `HandTracker.stop()`).

## HandSigns.swift
`HandSigns.shared` runs a `Hold` timer (0.8 s hold, 0.5 s re-arm, 0.15 s grace) on `sign(hand)` and runs the `SignAction` bound to the sign: copy, paste, play/pause, next/previous, volume, Mission Control, screenshot, or `.shortcut(name)`. `enabled` and `actions` persist in UserDefaults. It is silent while `cursorActive`. `HandSignsView` (Views/) is its page in the window; the menu bar only has its on/off switch.

## CameraStage.swift
| API | Example |
|---|---|
| `struct CameraStage<Content: View>` is the mirrored camera with the hand skeleton and face dots, filling its frame, with your content on top. It shows "Camera off" while Wave is off and a short message when access is denied. Used full size by Playground and full screen. | `CameraStage { size in MyOverlay(size: size) }` |
| `struct CameraCard` is the usual small camera: 16:9, rounded, optional fullscreen button and overlay. | `CameraCard(width: 360)` / `CameraCard(width: 480, onFullscreen: f) { banner }` |
| `struct CameraPreview: NSViewRepresentable` is the bare mirrored video. | `CameraPreview(authorized: t.authorized)` |
| `struct HandOverlay: View` draws joints, bones and `frame.faceLandmarks` dots. | `HandOverlay()` |
| `struct GestureBadge` is the dark "what the camera sees" capsule for large camera views. | `GestureBadge()` |
| `@Environment(\.snapshot)` is true while `--snapshot` renders. Skip camera, Metal, system prompts and clipboard reads when it is set. | `if !snapshot { … }` |

## Theme.swift
Native macOS look: system backgrounds, the user's accent colour, semantic colours (`.green` OK, `.orange` needs attention), default text styles. Pages are a `Form` with `.formStyle(.grouped)` where they can be.
| API | Example |
|---|---|
| `Theme.accent` is the system accent colour. `Theme.accent2` equals it (AirInk mixes the two). | `.foregroundStyle(Theme.accent)` |
| `Theme.spring` is the shared animation; `Theme.corner` (10) the corner radius. | `withAnimation(Theme.spring) { … }` |
| `.card(highlighted:)` is a platter like a grouped-form section, for cards outside a Form. | `row.card(highlighted: lit)` |

## Output.swift
| API | Example |
|---|---|
| `@discardableResult static func ensureAccessibility() -> Bool` prompts for Accessibility once. Key events are silently dropped without it. | `Output.ensureAccessibility()` |
| `static func key(_ code: CGKeyCode, flags: CGEventFlags = [])` sends a key down and key up. | `Output.key(49)` for space |
| `static func copy()` / `static func paste()` press ⌘C and ⌘V. | `Output.copy()` |
| `static func mediaKey(_ key: Int32)` takes `Output.NX_KEYTYPE_PLAY / NEXT / PREVIOUS / SOUND_UP / SOUND_DOWN`. | `Output.mediaKey(Output.NX_KEYTYPE_PLAY)` |
| `static func runShortcut(_ name: String)` runs an Apple Shortcut without waiting for it. | `Output.runShortcut("Focus")` |
| `static func listShortcuts() -> [String]` **blocks**, so call it off main. | `Task.detached { let s = Output.listShortcuts() }` |

## Rules for tab authors
- **Only edit your own files**: your view in `Views/` and new files in `Features/`. Do not edit `Core/` or `WaveApp.swift`. If you need a Core change, ask.
- Read state from `HandTracker.shared`. Never create another tracker or capture session.
- Register listeners in `.onAppear`, store the UUID, and call `removeListener` in `.onDisappear`.
- Send keys only through `Output`. Call `Output.ensureAccessibility()` before the first key you send.
- Respect `gesturesAllowed`. `onFrame` already does. If you act on `HandTracker.shared.gesture` directly, check `gesturesAllowed` first. Use `onAnyFrame` only for things that must run while gestures are blocked.
- Do not keep `frame.pixelBuffer` after the callback returns. Holding buffers starves the camera pool and freezes capture.
- Listener callbacks run on main every frame (about 30 fps), so keep them cheap.
- Run checks with `swift build && swift run Wave --selftest`. Render the UI without a camera with `scripts/snapshot.sh <dir>`, which writes each page in light and dark. To test the camera, use `./build.sh` and open `build/Wave.app`, because camera permission only works from the app bundle.
- Every `./build.sh` signs the app ad hoc again. After a rebuild, macOS may ask for the camera again, and Accessibility can silently stop working. If that happens, remove Wave from System Settings → Accessibility and add it back.
