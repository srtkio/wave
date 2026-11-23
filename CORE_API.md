# Wave Core API

Everything in `Sources/Wave/Core/`. Tab authors build on this and do not change it.

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
| `var detectFaces: Bool` (default false). Set it to true to fill `frame.face`. | `HandTracker.shared.detectFaces = true` |
| `var gesturesAllowed: Bool` (default true). The face check sets it to false to block gestures. | `guard t.gesturesAllowed else { return }` |
| `let session: AVCaptureSession` | used by `CameraPreview` |
| `func start()` asks for camera access and starts capture. It is safe to call more than once, and the app already calls it. | `HandTracker.shared.start()` |
| `@discardableResult func onFrame(_ f: @escaping (HandFrame, Gesture) -> Void) -> UUID` runs on main every frame, but **only while `gesturesAllowed`**. | `id = t.onFrame { frame, g in … }` |
| `@discardableResult func onAnyFrame(_ f: @escaping (HandFrame, Gesture) -> Void) -> UUID` runs on main every frame, always. It exists for the face check. | `id = t.onAnyFrame { frame, _ in … }` |
| `func removeListener(_ id: UUID)` removes a listener registered with either call. | `t.removeListener(id)` |

## CameraStage.swift
| API | Example |
|---|---|
| `struct CameraStage<Content: View>` is the one stage behind every tab, built once in `WaveRoot`. It shows the mirrored camera, the hand skeleton, the gesture badge (top-left), the "Raise a hand" hint, the camera-denied card, and your content. Tabs do **not** wrap themselves in it. | `CameraStage { size in MyTab(size: size) }` |
| `struct CameraPreview: NSViewRepresentable` is the bare mirrored video. | `CameraPreview(authorized: t.authorized)` |
| `struct HandOverlay: View` draws joints and bones. | `HandOverlay()` |
| `@Environment(\.snapshot)` is true while `--snapshot` renders. Skip camera, Metal, system prompts and clipboard reads when it is set. | `if !snapshot { … }` |

## Theme.swift
Every tab uses the same layout: one `Panel` pinned to the right column with `stageColumn()`.
| API | Example |
|---|---|
| `Panel(symbol:title:caption:) { … }` is the glass panel with the shared header, 360 pt wide. | `Panel(symbol: "bolt.fill", title: "Shortcuts", caption: "…") { … }.stageColumn()` |
| `.stageColumn()` pins a panel top-right, clear of the traffic lights and the tab bar (`Theme.insets`). | see above |
| `.panelScroll()` hugs the content when it fits and scrolls with soft edges when it doesn't. | `VStack { cards }.panelScroll()` |
| `.card(highlighted:)` is the lighter platter for cards inside a panel. `.glass()` is for things floating directly over the camera. | `row.card(highlighted: lit)` |
| `GlassButtonStyle(prominent:)` gives a capsule with hover and press states. `GlassToggleStyle` is applied app-wide. | `.buttonStyle(GlassButtonStyle(prominent: true))` |
| `Theme.title / heading / caption` are the type styles. | `Theme.caption("…")` |

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
- Run checks with `swift build && swift run Wave --selftest`. Render the UI without a camera with `swift run Wave --snapshot <dir>`, which writes one PNG per tab. To test the camera, use `./build.sh` and open `build/Wave.app`, because camera permission only works from the app bundle.
- Every `./build.sh` signs the app ad hoc again. After a rebuild, macOS may ask for the camera again, and Accessibility can silently stop working. If that happens, remove Wave from System Settings → Accessibility and add it back.
