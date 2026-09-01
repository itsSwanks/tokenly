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
- Auto-hide: slide distance 104 → **72px**; sliver bars 3×28 → **3×22px**.
- Gear icon 16 → 13px.

## 4. Callout compacted to match
- Width 480 → **320px**; padding **16px 18px**; radius 26 → **16px**; gap from dock ~24px.
- Header: glyph 17px + title 15px semibold, 14px below.
- Window blocks 14px apart: label 13px white / reset 12px gray; bar **5px** tall (radius 3); "% Used" **12px gray**, 6px above.
- Tail: 9px transparent / 11px solid.
- Exhausted reset line 14px; estimated footnote 11px; Connect row 13px text + 12px button.

Everything else (colors, semantic thresholds, timings, settings panel, banner, behaviors) is unchanged.
