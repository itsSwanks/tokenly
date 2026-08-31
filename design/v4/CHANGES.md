# Tokenly (formerly Pulse) — Design changes since first implementation

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


## 7. Settings panel — full redesign
See `Tokenly Settings Redesign.dc.html` (two variants: **1a dark vibrancy**, **1b light vibrancy** — build 1a as default and follow the system appearance if easy). The shipped panel reads like a kiosk: 22px type, 68px rows, green on every selected control, ungrouped rows floating on a bare sheet. Rebuild to macOS System Settings density:

**Container**
- Width 352px, radius 16px, padding 14px 14px 12px.
- Dark: `rgba(28,28,30,.82)` + `backdrop-filter: blur(40px) saturate(180%)`, 0.5px `rgba(255,255,255,.12)` border, shadow `0 22px 60px rgba(0,0,0,.45)` + inset top highlight. (Native: NSVisualEffectView `.popover`/`.hudWindow` material — let AppKit draw the vibrancy rather than a flat fill.)
- Light: `rgba(246,246,248,.86)`, 0.5px `rgba(0,0,0,.09)` border, shadow `0 22px 60px rgba(0,0,0,.22)`.

**Header** (replaces the "Pulse settings" title)
- App icon 19px (5px radius) + "Tokenly" 13px/600 + version "0.1.0" 11px in 40%-alpha gray, left; 20px circular close button right (`rgba(255,255,255,.1)`, hover .2), 9px ✕ glyph at 1.6px stroke.

**Grouped lists — the key change**
Three inset groups, each radius 10px on `rgba(255,255,255,.06)` (light: #fff + `0 0 0 0.5px rgba(0,0,0,.06)`), rows separated by 0.5px `rgba(255,255,255,.08)` hairlines (light `rgba(0,0,0,.07)`) — no separator above the first row. Only ONE section header survives: "PROVIDERS", 11px/600, +0.5px tracking, uppercase, 38%-alpha.

1. **Providers** — 38px rows: 2-line grip (11×1.5px bars, 30% alpha, `cursor: grab`) · 15px provider glyph (dimmed to 34% alpha when the provider is off) · name 13px/-0.08px tracking · live usage right-aligned 11px 35%-alpha tabular ("25%", "0%", "Off") · switch. Row hover `rgba(255,255,255,.05)`.
2. **Options** — 40px rows, label left / segmented control right. Rows replace the old stacked section headers entirely: "Alert threshold" (80/90/95%), "Screen edge" (Left/Right), "Dock style" (Notch/Glass), "Dock size" (S/M/L).
3. **Behavior** — 40px rows with 13px label + 11px 36%-alpha subtitle: "Auto-hide" / "Retract to a glass handle at the edge"; "Launch at login" / "Start Tokenly when you sign in"; "Automatic updates" / "Currently up to date" + an 11.5px "Check now" button (`rgba(255,255,255,.1)`, radius 6px) before its switch.

**Controls**
- Switch: 34×20px track, radius 10px, 17px white knob (top 1.5px, translateX 1.5→15.5px, .22s `cubic-bezier(.32,.72,0,1)`, shadow `0 1px 3px rgba(0,0,0,.28)`). ON = #32D74B, OFF = `rgba(255,255,255,.14)` (light #e3e3e7). Prefer the native NSSwitch.
- Segmented: track `rgba(255,255,255,.07)`, radius 7px, 2px padding, 2px gap; options 12px, 3.5px/11px padding, radius 5.5px. **Selected is NEUTRAL, never green** — dark: `rgba(255,255,255,.19)` + inset top highlight, weight 590; light: white + `0 1px 2px rgba(0,0,0,.12)`. Unselected text 50% alpha. Prefer native NSSegmentedControl.
- **Green is reserved for "on" (switches) and the semantic usage rings. Nothing else.**

**Footer**
- About copy demoted to an 11.5px/1.45 footnote at 42% alpha: "Reads usage from your local Claude, Codex and Gemini sign-ins. Talks only to those providers and to GitHub for updates. No analytics." (drop the "Pulse 0.1.0" heading — version now lives in the header).
- Row below: "View source on GitHub" 11.5px link (#7cc6d8 dark / #0066cc light) left; "Quit Tokenly" 11.5px right in 55%-alpha gray that turns red (#FF6961) on a `rgba(255,59,48,.16)` hover pill — not permanently red.

Net effect: same width, ~40% shorter, and the panel stops shouting.

### 7b. Appearance (light mode) — added
New **"Appearance"** row, FIRST row of the options group: segmented Auto / Light / Dark (default Auto = follow the system appearance). Persist with the other prefs. Auto must react live to system appearance changes.

Light theme applies to the dock, the callout and the settings panel. Semantic ring colors (#32D74B / #E4FF1A / #FF4F1F / #FF3B30) are IDENTICAL in both themes — usage color never changes meaning.

| Surface | Dark | Light |
|---|---|---|
| Dock (Notch) | `#0A0A0A` | `rgba(246,246,248,.94)` + blur(20px) saturate(180%) |
| Dock (Glass) | `rgba(16,16,18,.55)`, border `rgba(255,255,255,.14)` | `rgba(250,250,252,.6)`, border `rgba(0,0,0,.08)`, shadow `0 12px 36px rgba(0,0,0,.16)` + inset `0 1px 0 rgba(255,255,255,.7)` |
| Ring well (inner disc) | `#1C1C1E` | `#e8e8ed` |
| Ring track | `#2C2C2E` | `#dcdce1` |
| Primary text / glyphs | `#fff` | `#1d1d1f` |
| Secondary text | `#8E8E93` | `#8e8e93` |
| Callout pane | `rgba(16,16,18,.55)` | `rgba(250,250,252,.72)`, tail `rgba(250,250,252,.82)` |
| Settings pane | `rgba(20,20,22,.86)` | `rgba(246,246,248,.9)` |
| Switch OFF track | `rgba(255,255,255,.14)` | `#e3e3e7` |
| Segmented selected | `rgba(255,255,255,.19)` | `#fff` + `0 1px 2px rgba(0,0,0,.12)` |

Native note: prefer NSVisualEffectView materials + system colors (`labelColor`, `secondaryLabelColor`, `controlColor`) so both themes come free; the table is the fallback if you hand-roll.

The updated prototypes in this folder (`Pulse Edge Dock.dc.html`, `Tokenly Settings Redesign.dc.html`) both include Appearance — use them as the reference.
