# Pulse — Design changes since first implementation

Apply these to the existing app. Full updated spec is in README.md; updated prototype in `Pulse Edge Dock.dc.html`.

## 1. Callout material → frosted glass ("Glass frost")
- Background `rgba(16,16,18,.55)` + `backdrop-filter: blur(28px) saturate(160%)` (native: NSVisualEffectView / vibrancy, dark material).
- 1px border `rgba(255,255,255,.14)`; shadow `0 12px 36px rgba(0,0,0,.32)` + inset top highlight `rgba(255,255,255,.12)`.
- Tail color now `rgba(20,20,23,.72)` (translucent, matches glass).

## 2. New callout animation — "Glass frost"
- Panel fades in 300ms ease-out.
- Content de-blurs: opacity 0 + blur(14px) → sharp over 600ms `cubic-bezier(0.32,0.72,0,1)` (opacity fully in by 40% of the animation).
- The frost REPLAYS each time hover moves to a different ring, while the panel glides vertically (220ms transform) to the new ring. Replaces the old scale/slide-in entry.

## 3. Dock slimmed (was too big)
- Panel width 110 → **78px**; padding 26/14 → **18/10px**; cell gap 34 → **22px**; corner radius 30 → **22px**; concave corner flares 26 → **20px**.
- Ring 68 → **48px** ⌀ (r 22, stroke 5 → **3.5px**, circumference **138.23**); inner well r 23 → **16.5**; glyph ~26 → **~18px**.
- Percentage 26 → **16px** (exhausted "Limit reached" 11px); gap under ring 9 → 7px.
- Loading arc dasharray `32 106.23`; estimated dashed arc unchanged pattern (`2.6 4.2`), stroke 3.5.
- Auto-hide: dock now retracts FULLY off-screen when hidden (slide 104px; nothing of the panel or flares remains visible) — the glass handle below is the only resting UI.
- Gear icon 16 → 13px.

## 4. Callout compacted to match
- Width 480 → **320px**; padding **16px 18px**; radius 26 → **16px**; gap from dock ~24px.
- Header: glyph 17px + title 15px semibold, 14px below.
- Window blocks 14px apart: label 13px white / reset 12px gray; bar **5px** tall (radius 3); "% Used" **12px gray**, 6px above.
- Tail: 9px transparent / 11px solid.
- Exhausted reset line 14px; estimated footnote 11px; Connect row 13px text + 12px button.

## 5. New auto-hide collapsed UI — glass handle + glow dots
Replaces the old color-bar sliver. Resting state at the screen edge:
- 9px-wide frosted handle: `rgba(30,30,32,.5)` + `backdrop-filter: blur(14px)`, 1px border `rgba(255,255,255,.16)`, radius 6px on the inward side, padding 14px 0.
- Inside, one 5px glow dot per enabled provider, 13px gap, semantic color + `box-shadow: 0 0 9px <color>` (gray #5a5a5e when disconnected/loading).
- Crossfade with the dock: handle opacity 1→0 over 250ms as dock slides out; reverse on hide. Mirrors on left edge.

## 6. Dock style setting — Notch / Glass
New "Dock style" segmented control in settings (default Notch):
- **Notch** — existing opaque #0A0A0A panel with concave corner flares.
- **Glass** — frosted slab: `rgba(16,16,18,.55)` + `backdrop-filter: blur(28px) saturate(160%)`, 1px `rgba(255,255,255,.14)` border, shadow `0 12px 36px rgba(0,0,0,.3)` + inset top highlight, NO flares, same 22px inward radius.
Persist the choice with the user's other preferences.

Everything else (colors, semantic thresholds, timings, settings panel, banner, behaviors) is unchanged.
