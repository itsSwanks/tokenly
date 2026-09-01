# Design prompt — paste this into Claude (attach `reference-mockup.png`)

---

Build me a **fully interactive, working prototype** of a macOS desktop utility called **Pulse** — an edge dock that shows how much of your AI subscription limits you have left, at a glance.

Deliver it as **one self-contained HTML artifact** (inline CSS + vanilla JS, no external libraries, no network requests, all icons as inline SVG). It must actually run and respond — not a static picture.

I've attached a reference mockup. **Match it closely.** It is the source of truth for the visual language. Read the spec below as the precise description of what's in that image.

---

## 1. The stage

The artifact renders a **simulated macOS desktop** so I can judge the dock in context:

- Full-bleed desktop with a **rounded screen corner** (radius ~44px) and a soft drop shadow, sitting on a light dotted-grid backdrop — exactly like the reference framing.
- Wallpaper: a rich **aurora / light-streak gradient** (deep teal and cyan flowing into orange and gold streaks) with a subtle film-grain noise overlay. Generate it in CSS/SVG — no image files.
- A macOS **menu bar** across the top: right-aligned muted-speaker, Wi-Fi, account, search, and Control Center glyphs, then a live-ticking `Thu 27 Aug 11.22` clock. Black glyphs over the light part of the wallpaper.
- A couple of faint window chrome hints behind the dock are welcome but optional. Don't let them compete.

## 2. The dock — the core object

A **black panel flush against the right edge of the screen**, vertically centered.

- Background: near-pure black (`#0A0A0A`), fully opaque.
- Shape: the left side has a large corner radius (~30px); where the panel meets the screen edge, the top and bottom flare out with **inverted / concave corners** so it reads as *grown out of the edge*, not stuck on top of it. That concave blend is the signature detail — get it right (SVG path or CSS radial-gradient corner masks both work).
- Width ~110px. Height fits its contents with generous padding (~22px sides, ~26px top/bottom).
- Contents: a vertical stack of **provider cells**, ~34px apart.

**Each provider cell:**
- A **progress ring**: ~68px diameter, ~5px stroke, round line caps. Track is `#2C2C2E`. The arc starts at 12 o'clock and sweeps **clockwise** by the used percentage.
- Inside the ring, a **dark circular well** (`#1C1C1E`) holding the provider's monochrome white glyph at ~26px:
  - **Claude** — the eight-point asterisk / starburst
  - **OpenAI** — the six-petal knot flower
  - **Grok** — the angular slashed-diamond mark
  - **Gemini** — the four-point sparkle
- Below the ring, the percentage in white SF Pro–style type, ~26px, medium weight: `73%`.

**Ring color is semantic, not brand** — it encodes urgency:
- `0–39%` → green `#32D74B`
- `40–69%` → yellow `#E4FF1A`
- `70–89%` → orange-red `#FF4F1F`
- `90–100%` → red `#FF3B30`, and the ring **pulses** slowly (2s ease-in-out breathing on opacity/glow)

In the reference: Claude 73% orange-red, OpenAI 21% green, Grok 52% yellow. Reproduce those exact values as the default state.

## 3. The callout

Hovering a ring opens a **detail callout** to the left of the dock, with a **solid triangular tail** pointing at the hovered ring.

- Black rounded rect, radius ~26px, ~560px wide, ~26px padding.
- Header row: the provider glyph + `Claude Usage` in white, ~22px medium.
- Then one block per limit window. Claude has two:
  - Row 1: label `Current session` (white, 17px) on the left, `Resets in 51 min` (gray `#8E8E93`, 17px) right-aligned.
  - A full-width **progress bar**: 7px tall, fully rounded caps, track `#2C2C2E`, fill in the same semantic color as the ring, width = used %.
  - Below it: `73% Used` in white, 16px.
  - Repeat for `All models` / `Resets Thu 12:00 AM` / green fill at 7% / `7% Used`.
- The callout animates in: 160ms, slight scale-up from 0.96 plus a few px of travel toward the cursor, opacity 0→1. Out is faster, ~110ms.
- It follows vertically to align its tail with whichever ring is hovered.

Each provider gets sensible windows: Claude → *Current session* + *All models*. OpenAI → *GPT-5 messages* + *Deep research*. Grok → *Current window*. Gemini → *Daily quota*.

## 4. Interaction — this is what makes it a prototype, not a picture

Make all of this genuinely work:

1. **Edge peek.** The dock's default resting state is a thin 5px sliver at the screen edge, showing only stubby color-coded arc fragments. Moving the cursor into the right ~40px of the screen **slides the full dock out** (260ms, spring-ish easing). Moving away retracts it after a 400ms grace delay. Include a toggle to switch between *Auto-hide* and *Always visible*.
2. **Hover a ring** → callout opens, as above. Moving between rings slides the callout rather than re-opening it.
3. **Click a ring** → pins the callout open until dismissed.
4. **Drag the dock vertically** along the edge; it snaps back inside screen bounds. Position persists in memory for the session.
5. **Live data.** Reset countdowns tick down in real time. Usage creeps upward on a slow simulated interval so I can watch a ring cross a color threshold and start pulsing.
6. **Right-click / gear** → a settings panel styled to match: reorder providers by drag, toggle each on/off, choose alert thresholds (80% / 95%), pick left or right edge, switch auto-hide mode.
7. **Threshold alert.** When a provider crosses 90%, show a native-looking macOS notification banner sliding in from the top right, then auto-dismissing.

## 5. States I need to see

Add a small floating **demo control strip** (outside the simulated screen, clearly a dev tool, not part of the product) that lets me force each state:

- **Normal** — the reference state
- **Near limit** — Claude at 94%, pulsing red, alert banner fired
- **Exhausted** — Claude at 100%: ring solid red, `0%` replaced by a `Limit reached` label, callout shows `Resets in 12 min` prominently
- **Estimated data** — OpenAI, Grok and Gemini rendered with a **dashed ring** and a small `~` before the percentage, callout carrying a gray `Estimated — based on local activity` footnote. This matters: only Claude has a real usage feed; everything else is inferred, and the UI must never pretend otherwise.
- **Disconnected** — a provider not signed in: gray dashed ring, `—` instead of a percentage, callout offering a `Connect` button
- **Loading** — a shimmering indeterminate ring on first launch
- **Light wallpaper** — swap to a pale wallpaper to prove the black dock still reads well
- **Left edge** — the whole dock mirrored to the left screen edge, callout and tail flipped

## 6. Craft bar

- Every color, radius, and duration comes from CSS custom properties declared once at the top.
- Real easing: `cubic-bezier(0.32, 0.72, 0, 1)` for slides, not `linear` or `ease`.
- Ring arcs animate their sweep when values change — no snapping.
- Typography is the system stack: `-apple-system, "SF Pro Text", "Helvetica Neue"`. Tabular numerals on every percentage so digits don't jitter as they tick.
- Respect `prefers-reduced-motion` — kill pulses and shorten transitions.
- Rings need `role="progressbar"` with `aria-valuenow` and real labels.
- 60fps: animate `transform` and `opacity` only, never `width`/`top`.

## 7. What matters most

This is a glanceable ambient object. It should feel like something Apple shipped — restrained, precise, physically attached to the edge of the display. The reference mockup already nails the feel. **Don't redesign it, realize it.** No gradients on the panel, no glassmorphism, no accent colors beyond the semantic ring states, no explanatory chrome.

Ship the whole thing in one artifact, working, on the first pass.
