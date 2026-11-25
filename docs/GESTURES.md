# Wave gesture guide

All timings and thresholds below are the values in the code. They were chosen without real-camera tuning, so expect them to move. Distances are measured relative to **palm size** (wrist to middle knuckle), so they work at any distance from the camera.

## Good tracking

- **Light**: face a window or lamp. A backlit hand becomes a silhouette and Vision loses fingers.
- **Distance**: about an arm's length. A hand whose palm is under 8% of the frame is treated as far away and ignored (that is how people behind you are filtered). If Wave ignores you, move your hand closer.
- **Small moves are enough**: cursor mode works like a trackpad. It follows how your hand *moves* (in palm-widths), not where it is, so you never need to reach the edges of the frame, and it feels the same near or far from the camera.
- **Face the palm or the back of the hand toward the camera**, with fingers visible. A fist or a pinch that hides the thumb tip is read as "lost".
- **Only the closest hand counts.** With two hands in view the larger (closer) one is the main hand.
- A gesture is accepted after it is seen in **3 frames in a row**, which filters flicker.

## Cursor mode

### Start
Hold a thumb + index pinch (tips closer than **0.25** palm) for **0.6 s** without letting the index knuckle drift more than **4%** of the frame. A ring fills in the notch. Open your hand to cancel. After it starts, you must open the pinch before anything else happens.

### While on
| Action | Exact rule |
|---|---|
| Move | Trackpad-style. The index knuckle's motion, in palm-widths, moves the cursor with acceleration: slow ≈ **0.35** screen widths per palm-width (about 6 px per mm), rising **0.5** per palm-width/s of hand speed, up to **2.0**. Scaled by the **Speed** slider on the Cursor page (0.5–2.5). Motion under **0.06** palm-widths/s counts as stillness (no drift). Smoothed with a One Euro filter (min cutoff 0.6 Hz), and the pointer glides at 120 Hz between camera frames. Starts from wherever the pointer already is. |
| Pinch | Closed below **0.25** palm, counts as open again above **0.40** (hysteresis stops flicker). |
| Left click | Thumb + index pinch held **0.05 to 0.3 s** then released. Shorter is treated as flicker. |
| Double-click | A second click within **0.4 s**, within 2% of the screen of the first. |
| Right click | Same tap with thumb + **middle** finger (index must stay open). |
| Drag | Index pinch held **over 0.3 s**: button goes down, the cursor follows your hand, releasing the pinch lets go. |
| Click aim | When a pinch begins the cursor is pinned to where it was **0.1 s earlier**, undoing the nudge from closing your fingers. |
| Scroll | Make a peace sign (index and middle up) for **0.15 s**. Where your knuckle is at that moment is the centre. Moving away from it scrolls that way. Inside a dead zone of **0.3** palm nothing happens; beyond it speed is `2500 x excess^1.5` px/s, capped at **4000** px/s. Dropping the sign for **0.25 s** ends scrolling. |
| Exit | **Both hands** pinching (below 0.40), more than 10% of the frame apart sideways and within 15% vertically, held **2 s**. A ring fills in the notch. |
| Hand lost | After **1.5 s** without a hand, cursor mode pauses (drag released); showing your hand again resumes it. After **20 s** it exits. |
| Turning Wave off | Ends cursor mode immediately and releases any held button. |

Hand signs and the optional window features are paused while cursor mode is on.

## Hand signs

Outside cursor mode only. A sign must be **held 0.8 s**; the ring in the notch shows progress. After an action fires, the hand must leave the sign for **0.5 s** before it can fire again. A dropout shorter than **0.15 s** does not reset the hold. Switching to a different sign restarts the clock, so a sign you pass through never fires.

| Sign | How to make it | Default action |
|---|---|---|
| 👍 Thumbs up | Fist with the thumb up; thumb tip at least 0.3 palm above the index knuckle (a sideways thumb is not a thumbs up) | Play / pause |
| 🤘 Rock | Index and little finger up, middle and ring curled, thumb free | Next track |
| 🤙 Call me | Thumb and little finger out, the other three curled | Mission Control |
| ✌️ Peace | Index and middle up, ring and little curled, thumb free | Full-screen screenshot (⌘⇧3), saved where your screenshots normally go; the notch pill is kept out of the shot |
| 👌 OK | Thumb tip touching the index tip (under 0.3 palm) with middle, ring and little up | Copy |
| 🇱 L | Thumb and index out, others curled, at roughly a right angle (about 53 to 127 degrees) | Paste |

A thumb + index pinch with the other fingers curled is a plain pinch, not a sign.

Finger detection: a finger is "up" when its tip is more than **1.1 x** as far from the wrist as its middle joint. The thumb is "out" when its tip is more than **0.5** palm from the index knuckle.

Actions available for every sign: nothing, copy, paste, play/pause, next track, previous track, volume up, volume down, Mission Control, screenshot, or any Apple Shortcut. Changes are saved. Sending keys needs Accessibility.

## Troubleshooting

- **Nothing happens.** Check the menu bar: is **Wave** switched on? The status line should say "Looking for your hand…" or "Seeing: …".
- **Status says camera access is off.** Allow Camera for Wave in System Settings → Privacy & Security → Camera.
- **Hand is seen but clicks, keys or media do nothing.** Wave needs **Accessibility**. Grant it in System Settings → Privacy & Security → Accessibility. After rebuilding with `./build.sh` the ad hoc signature changes and macOS can silently drop the grant: remove Wave from the list and add it again.
- **Hand is ignored.** It is probably too far away (palm under 8% of the frame). Move closer.
- **Cursor mode will not start.** Keep your hand steady for the full 0.6 s and make a firm pinch. If the ring keeps resetting, you are moving more than 4% of the frame while holding. If both hands pinch, it counts as the exit pose and will not arm.
- **Taps are missed or become drags.** A tap must be quick (0.05 to 0.3 s). Hold longer than 0.3 s and it becomes a drag.
- **A sign does not fire.** Hold it for the full 0.8 s with the whole hand in view. Check its action is not set to "Nothing", and that Hand signs is switched on in the menu.
- **Signs do nothing in cursor mode.** That is by design; exit cursor mode first.
- **Scrolling goes the wrong way.** The direction assumes posted events skip natural-scroll inversion; this is an untested guess on real hardware.
- **Someone behind me triggers it.** Shouldn't happen: only the closest hand counts. If it does, the other hand is larger than 8% of the frame, so move a little closer yourself.
