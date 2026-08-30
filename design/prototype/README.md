# Handoff: Pulse — AI Usage Edge Dock (macOS utility)

## Overview
Pulse is a macOS desktop utility: a black dock attached to the screen edge showing, at a glance, how much of each AI subscription's usage limit remains (Claude, OpenAI, Grok, Gemini). Hovering a ring opens a detail callout; the dock auto-hides to a sliver, is draggable along the edge, and fires notification banners at alert thresholds.

## About the Design Files
The files in this bundle are **design references created in HTML** — a working prototype showing intended look and behavior, not production code to ship. The task is to **recreate this design in the target environment** (a real macOS app: Swift/SwiftUI + NSPanel is the natural fit — a borderless, non-activating panel pinned to the screen edge; Electron/Tauri also workable). If no codebase exists yet, choose the most appropriate stack for a menu-bar/edge utility.

`Pulse Edge Dock.dc.html` is the prototype. Ignore its framework scaffolding (`support.js`, `<x-dc>`, `{{ }}` template holes, the `Component` logic class) — treat it as the source of truth for geometry, colors, timing, and behavior. The simulated desktop (wallpaper, menu bar, dotted backdrop) and the DEMO control strip are **stage/dev chrome only — do not build them**; the real product is only the dock, callout, settings panel, and notification banner.

## Fidelity
**High-fidelity.** Colors, sizes, spacing, easing, and copy are final. Recreate pixel-perfectly.

## Screens / Views

### 1. The dock (core object)
- Black panel (`#0A0A0A`, fully opaque) flush against the right screen edge, vertically centered by default.
- Width 110px. Padding 26px top, 14px bottom. Vertical stack of provider cells, 34px gap, centered.
- Corner radius 30px on the screen-facing-inward side (`30px 0 0 30px` on right edge; mirrored on left).
- **Signature detail — concave flares:** where the panel meets the screen edge, top and bottom flare outward with inverted corners so the dock reads as grown out of the edge. Prototype technique: two 26×26px elements above/below the panel at the edge, `background: radial-gradient(circle 26px at 0% 0%, transparent 25.4px, #0A0A0A 26px)` (circle anchored at the corner away from edge+dock; four variants for top/bottom × left/right edge).

**Provider cell:**
- Progress ring: 68px SVG, radius 31.5, stroke 5px, round line caps. Track `#2C2C2E`. Arc starts at 12 o'clock, sweeps clockwise by used % (circle with `stroke-dasharray: 197.92` = circumference, `stroke-dashoffset: C × (1 − pct/100)`, rotated −90°). Dashoffset transitions 0.7s on value change — never snaps.
- Inner well: circle r=23, `#1C1C1E`, holding the provider's monochrome white glyph (~26px). Glyphs in the prototype are simplified original marks (8-ray asterisk, 6-petal outline flower, slashed diamond, 4-point sparkle) drawn programmatically — swap for licensed brand assets if available.
- Percentage below: white, 26px, weight 500, `font-variant-numeric: tabular-nums`, 9px gap.

**Ring color is semantic (urgency), never brand:**
- 0–39% → green `#32D74B`
- 40–69% → yellow `#E4FF1A`
- 70–89% → orange-red `#FF4F1F`
- 90–100% → red `#FF3B30` + slow pulse (2s ease-in-out opacity 1 → 0.4 → 1) while 90 ≤ pct < 100

Default demo state: Claude 73% (orange-red), OpenAI 21% (green), Grok 52% (yellow). Gemini disabled.

### 2. The callout
Opens on ring hover, left of the dock (26px gap from panel; prototype: `right: 136px` inside the screen), with a solid triangular tail pointing at the hovered ring (borders trick: 13px transparent top/bottom + 16px solid `#0A0A0A` toward the dock).
- Black `#0A0A0A` rounded rect, radius 26px, 560px wide, 26px padding, shadow `0 18px 50px rgba(0,0,0,.45)`.
- Header: 24px provider glyph + "{Provider} Usage", white 22px weight 500, 20px below.
- Per limit window (20px between blocks):
  - Row: label (white 17px) left, reset text (gray `#8E8E93` 17px, tabular-nums) right, 10px below.
  - Bar: 7px tall, fully rounded, track `#2C2C2E`; fill in that window's own semantic color, width = pct (animate via `transform: scaleX`, origin left, 0.7s).
  - "{pct}% Used", white 16px, 9px above.
- Entry animation: 160ms `cubic-bezier(0.32,0.72,0,1)`, scale 0.96→1 + ~10px travel toward cursor, opacity 0→1. Exit ~110ms. Moving between rings **slides** the callout vertically (transform transition 220ms) instead of re-opening.
- Click a ring pins the callout until click-away or re-click.

**Limit windows per provider:** Claude → Current session (resets in 51 min) + All models (Resets Thu 12:00 AM). OpenAI → GPT-5 messages + Deep research. Grok → Current window. Gemini → Daily quota.

### 3. Settings panel (right-click dock or gear button at dock bottom)
Black `#0A0A0A`, radius 22px, 300px wide, 20px padding, near the dock.
- Provider rows: drag handle (reorder by drag), 18px glyph, name (15px), iOS-style toggle (38×23px pill, knob 19px, green `#32D74B` when on).
- "Alert threshold" segmented: 80% / 90% / 95% (default 90).
- "Screen edge" segmented: Left / Right.
- "Auto-hide" toggle.
- Section labels: 12px uppercase gray, 0.6px letter-spacing.

### 4. Notification banner
macOS-style, slides in from top-right when a provider crosses the alert threshold (and again at 100%): `rgba(245,245,247,.92)` + 20px backdrop blur, radius 14px, 330px wide, 34px black app-icon tile with provider glyph, title "Pulse" 13px semibold, message 13px. Enters 350ms (opacity + 46px translateX), auto-dismisses after ~4.6s.

## Interactions & Behavior
1. **Edge peek (auto-hide mode):** resting state is a ~6px sliver at the edge showing only 3×28px color-coded bars (one per provider, semantic color). Cursor within ~44px of the edge slides the dock out (260ms, `cubic-bezier(0.32,0.72,0,1)`, translateX 104px). Retracts after a 400ms grace delay once the cursor leaves the dock region (>200px away), unless a callout is pinned or settings are open. Toggle between Auto-hide / Always visible.
2. **Hover ring** → callout opens; between rings it slides. 140ms grace when leaving so the cursor can travel into the callout.
3. **Click ring** → pins/unpins callout.
4. **Drag dock vertically** (5px movement threshold so clicks still work); clamped inside screen bounds; position persists for the session. Click after drag must not trigger pin.
5. **Live data:** reset countdowns tick every second ("Resets in N min", "Resets in H h M min", "Resets in <1 min"; window resets roll pct back to ~1–5% and re-arm). Usage creeps up ~0.1–0.4%/2.5s so rings visibly cross color thresholds.
6. **Threshold alert** fires the banner exactly once per crossing.

## States
- **Normal** — defaults above.
- **Near limit** — ≥90%: red ring, 2s pulse, banner fired.
- **Exhausted** — 100%: solid red ring (no pulse), percentage replaced by "Limit reached" (14px), callout shows "Resets in 12 min" prominently (red 20px semibold under header).
- **Estimated** — only Claude has a real usage feed; others are inferred. Dashed arc (SVG path arc, `pathLength=100`, `stroke-dasharray: 2.6 4.2`), `~` before the percentage, gray callout footnote "Estimated — based on local activity" (14px `#8E8E93`). **The UI must never present estimated data as real.**
- **Disconnected** — gray (`#5a5a5e`) dashed track (`3.4 4.6`), "—" instead of pct, callout: "Not signed in. Connect to see usage." + Connect button (`#2C2C2E` pill, hover `#3a3a3d`).
- **Loading** — first launch: indeterminate gray arc (dasharray `46 151.92`) spinning 1.1s linear.
- **Left edge** — everything mirrors: panel radius, flares, callout side, tail, sliver bars, slide direction.

## State Management
- `providers`: ordered list; each: `{name, enabled, status: live|disconnected|loading, estimated, windows: [{label, pct, resetAt|fixedText, durationMin}]}`
- UI state: `edge (left|right)`, `autoHide`, `expanded`, `dockY`, `hoverProvider`, `pinnedProvider`, `settingsOpen`, `alertThreshold (80|90|95)`, `banner`
- Timers: 1s tick (countdowns/resets), usage poll, 400ms collapse grace, 140ms hover grace, ~4.6s banner dismiss.
- Real data source: Claude usage API/feed for real numbers; local activity heuristics for estimated providers.

## Design Tokens
- `--panel: #0A0A0A` · `--well: #1C1C1E` · `--track: #2C2C2E` · `--gray: #8E8E93`
- Semantic: green `#32D74B`, yellow `#E4FF1A`, orange `#FF4F1F`, red `#FF3B30`
- Easing: `cubic-bezier(0.32, 0.72, 0, 1)` for all slides/sweeps
- Durations: dock slide 260ms, callout in 160ms / out 110ms / follow 220ms, ring sweep 700ms, pulse 2s, banner in 350ms
- Radii: panel 30px, callout 26px, settings 22px, banner 14px, bars 4px, screen corner (context only) 44px
- Type: system stack `-apple-system, "SF Pro Text", "Helvetica Neue"`; sizes 26 (pct), 22 (callout header), 17 (rows), 16 (used), 15 (settings), 14 (footnote/exhausted label), 13 (banner), 12 (section labels). Tabular numerals on every number.
- Ring: 68px ⌀, r 31.5, stroke 5, circumference 197.92.

## Craft requirements
- Respect `prefers-reduced-motion`: kill pulses, near-zero transition durations.
- Rings: `role="progressbar"`, `aria-valuenow`, real labels ("Claude usage 73 percent").
- 60fps: animate `transform`/`opacity` only (bar fills use scaleX, dock uses translateX).
- No gradients on the panel, no glassmorphism, no accent colors beyond the semantic states.

## Screenshots
In `screenshots/` — captured from the running prototype (the dotted backdrop, simulated desktop, and bottom DEMO strip are stage chrome, not product):
1. `01-normal-callout.png` — default state, Claude callout open
2. `02-near-limit.png` — Claude ≥90%, pulsing red + notification banner
3. `03-exhausted-callout.png` — 100%, "Limit reached", callout with prominent reset
4. `04-estimated-callout.png` — dashed rings, ~ prefix, estimated footnote
5. `05-disconnected-callout.png` — gray dashed ring, "—", Connect button
6. `06-loading.png` — indeterminate spinning arcs
7. `07-light-wallpaper.png` — dock contrast on pale wallpaper
8. `08-left-edge.png` — fully mirrored to left edge
9. `09-settings-panel.png` — settings: reorder, toggles, threshold, edge, auto-hide

## Assets
- `reference-mockup.png` — original visual reference (source of truth for feel).
- Provider glyphs: generated in code in the prototype (see `glyph()` in the logic class); replace with proper brand marks per each provider's usage guidelines.
- No other image assets; wallpaper/noise in the prototype are stage-only CSS.

## Files
- `Pulse Edge Dock.dc.html` — the full working prototype (template = markup/styles; `Component` class = all behavior).
- `ORIGINAL-DESIGN-PROMPT.md` — the original written spec.
- `reference-mockup.png` — reference mockup.
