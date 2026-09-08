# Conditional OS lang switch on Lower/Raise (only when ZMK is RU)

**Status:** research only — no firmware edits  
**Repo:** `charybdis-colemak-rus`  
**Date:** 2026-09-07  
**Related code:** `zmk_extra_modules/lang_switch_freeze/`, `config/behaviors/behavior_esc_layer_switch.dtsi`, `config/charybdis.keymap`

---

## Problem statement

Lower / Raise should force the **OS** input language to English **only when the firmware believes the base layout is Russian**. If the ZMK default/base is already Colemak (EN), pressing Lower/Raise must **not** emit a language-switch HID sequence.

Today the dongle module always sends “go English” on Lower/Raise **press**, regardless of whether the Russian layer is active. Release already restores Russian only when the Russian layer is active — asymmetric and the source of the bug/UX complaint.

Symptom surface (user-facing):

- On Colemak: every Lower/Raise press still fires Alt+Shift+1 (via encoded `LA(LS(N1))`), plus mod release + ~50 ms input freeze.
- Even if the OS hotkey is *absolute* (idempotent), the side effects (freeze drop, mod clear, possible OS UI flicker / focus quirks) still happen when already EN.
- If the host is misconfigured and treats the chord as a **toggle**, pressing Lower/Raise from EN can flip OS lang to RU while the ZMK layer stays Colemak → desync and “floating” symbols.

---

## Current architecture (what the firmware actually tracks)

### Layer mirror, not OS language

ZMK has **no** native notion of “current OS keyboard language.” Layers are local firmware state. Host layout is inferred by convention: Colemak layer ↔ EN, Russian layer ↔ RU, and OS is nudged with HID chords.

Primary evidence that OS → keyboard lang feedback is not in ZMK:

- Upstream request: [zmkfirmware/zmk#1716 — “can we know which input source (current language) from OS?”](https://github.com/zmkfirmware/zmk/issues/1716) — consensus is HID is effectively one-way for this; would need a host companion + bidirectional channel (e.g. Raw HID).
- ZMK system HID config exposes LED indicators (`CONFIG_ZMK_HID_INDICATORS`: Caps/Num/Scroll), not input-language state — [ZMK System Configuration](https://zmk.dev/docs/config/system).
- USB HID `bCountryCode` is a static localization hint and is widely ignored by OSes; it does **not** command the host to switch layout — [Stack Overflow / HID discussion](https://stackoverflow.com/questions/39388141/send-language-layout-from-usb-hid-keyboard), [Deskthority](https://deskthority.net/viewtopic.php?t=21960).

**Conclusion:** this repo only has a **ZMK layer mirror** of language. There is no reliable “current OS lang” bit unless you add host software.

### Layer indices (source of truth for “RU?”)

From `config/charybdis.keymap`:

| Index | Name | Role in lang story |
|------:|------|--------------------|
| 0 | Colemak | EN mirror (`&to 0` after OS EN) |
| 1 | Russian | RU mirror (`&to 1` after OS RU) |
| 3 | Lower | Symbol layer; wants **OS EN** while held (from RU) |
| 4 | Raise | Same idea |
| 9 | CtrlColemak | RU-only Ctrl remap; **does not** touch OS lang (`behavior_ru_ctrl.dtsi`) |

Explicit EN/RU switches (Esc-hold thumbs):

- Colemak: `&to_rus` → hold runs `macro_to_rus` → release mods → Alt+Shift+N2 → `&to 1`
- Russian: `&to_eng` → hold runs `macro_to_eng` → release mods → Alt+Shift+N1 → `&to 0`

Defined in `config/behaviors/behavior_esc_layer_switch.dtsi`.

### `lang_switch_freeze` (Lower/Raise path)

Runs on **dongle** (`CONFIG_ZMK_LANG_SWITCH_FREEZE=y` in `charybdis_dongle.conf`; sources wired from `boards/shields/charybdis/CMakeLists.txt`).

Logic today (`lang_switch_freeze.c`):

```text
on position Lower(37) or Raise(40):
  PRESS:
    freeze input ~FREEZE_MS
    ALWAYS submit lang_to_eng_work   → release all mods → sleep 5ms → tap LA(LS(N1))
  RELEASE:
    if zmk_keymap_layer_active(RUSSIAN_LAYER=1):
      freeze again
      submit lang_to_rus_work        → release mods → sleep 5ms → tap LA(LS(N2))
    else:
      no OS chord
```

| Event | Condition | OS chord | Matches desired? |
|-------|-----------|----------|------------------|
| Lower/Raise press | **none** | always EN (`LA(LS(N1))`) | **No** — should only when RU |
| Lower/Raise release | `layer_active(1)` | RU (`LA(LS(N2))`) | Yes (restore after RU→EN temporary) |
| Esc hold EN/RU | user intent | absolute EN/RU + `&to` | Separate path; already absolute |

Kconfig (defaults): `LOWER_POS=37`, `RAISE_POS=40`, `RUSSIAN_LAYER=1`, `FREEZE_MS=50`, `COMBO_MS=35` (note: `COMBO_MS` is defined in Kconfig but **unused** in the `.c` file).

Documented intent in `todo.md` / `todo-priority.md`: “зажал Lower/Raise → EN; отпустил на русском → RU.” The missing gate on press is exactly this research item.

### How `zmk_keymap_layer_active(1)` behaves with `&mo`

- Default layer Russian (`&to 1`) + `&mo LOWER`: Russian stays active (default), Lower activates on top → release path correctly sees RU and restores OS RU.
- Default Colemak (`&to 0`) + `&mo LOWER`: Russian inactive → release skips RU chord (good).
- Auto-mouse / Mouse with `&trans` thumbs: position listener still fires on physical Lower/Raise positions; if default is RU, press still always EN today (desired for symbols); if default is EN, press still always EN (undesired noise).

Firmware **never** reads OS lang; it only asks “is ZMK Russian layer active?”

### Two different HID encodings for the same chord

| Path | Sequence |
|------|----------|
| Esc macros (`macro_os_eng` / `macro_os_rus`) | press LALT+LSHFT → tap N1/N2 → release mods |
| `lang_switch_freeze` | single encoded tap `LA(LS(N1))` / `LA(LS(N2))` |

Same intent (absolute layout hotkeys), different timing/report shape. Worth knowing when debugging OS recognition, but not the root of the “always switch” bug.

---

## Root cause (one line)

**Press path unconditionally calls `send_os_english()`; it never consults `zmk_keymap_layer_active(RUSSIAN_LAYER)` the way the release path does.**

Desired press semantics:

```text
PRESS Lower/Raise:
  if Russian layer active:
    freeze + send OS EN
  else:
    do nothing for language (optional: still freeze or not — product choice)
RELEASE Lower/Raise:
  if Russian layer active:   # unchanged
    freeze + send OS RU
```

---

## Host-side reality: toggle vs absolute

Firmware already *aims* at **absolute** selection (`…+1` = EN, `…+2` = RU), not Win+Space / bare Alt+Shift cycle. That only works if the **host** is configured that way.

### Windows

- Default **Left Alt+Shift** = cycle “Between input languages” (toggle/cycle) — [Digital Citizen Win11](https://www.digitalcitizen.life/change-keyboard-language-shortcut-windows-11/), [Win10](https://www.digitalcitizen.life/keyboard-language-shortcut/).
- **Win+Space** = also a cycle UI, not absolute.
- Absolute: Settings → Time & language → Typing → Advanced keyboard settings → **Input language hot keys** → per-layout “To English…”, “To Russian…” → Enable Key Sequence → e.g. Left Alt+Shift+1 / +2 — same docs as above; also [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/4124976/exclude-specific-keyboard-layourt-from-shortcut) recommending per-language hotkeys instead of cycle.

**Repo assumption:** OS has Alt+Shift+1 → EN, Alt+Shift+2 → RU. Re-sending EN while already EN is usually a no-op for layout, but still costs freeze/mod-release and can surprise if hotkeys aren’t set (bare Alt+Shift falls through to cycle → disaster).

### Linux

- **Toggle/cycle:** desktop “next input source” shortcuts.
- **Absolute (X11 classic):** `setxkbmap us` / `setxkbmap ru` — layout changes, but on modern GNOME Shell the indicator/shortcuts often desync — [madhead / Shyriiwook](https://github.com/madhead/shyriiwook), [madhead write-up](https://madhead.me/posts/shyriiwook/).
- **`gsettings … input-sources current`:** widely cited as **broken/deprecated** on current GNOME.
- **Absolute on GNOME (practical):** Shell extension exposing D-Bus activate-by-id, e.g. Shyriiwook `me.madhead.Shyriiwook.activate "us"` / `"ru"`, bound to custom shortcuts that the keyboard can emit — or a companion that listens for a dedicated key and calls D-Bus.
- Pure Wayland/GNOME: firmware cannot set layout via HID language report; only key chords or out-of-band IPC.

### macOS

Out of primary scope for this Windows-oriented repo, but same pattern: Input Source shortcuts can be absolute per source; bare cycle shortcuts are toggles. ZMK#1716 discusses host→keyboard sync via tools like `macism` + companion, not HID alone.

### HID “language report”

There is **no** standard HID report that OSes honor to set the active input language. Options remain: (1) key chords the OS already maps, (2) host agent (Raw HID / proprietary), (3) ignore OS and only remap keycodes in firmware (wrong model for Cyrillic vs Latin — OS must interpret scan codes).

`zmk-layout-shift` ([kot149/zmk-layout-shift](https://github.com/kot149/zmk-layout-shift)) remaps **keycodes for a fixed OS layout** (e.g. US keycaps on JIS OS). It does **not** switch OS language and does not solve EN/RU OS sync.

---

## Approaches (ranked)

### Rank 1 — Gate EN chord on Russian layer (minimal fix) ✅ recommended

**Change:** in `position_listener`, only submit `lang_to_eng_work` when `zmk_keymap_layer_active(RUSSIAN_LAYER)`.

```c
if (ev->state) {
    if (zmk_keymap_layer_active(RUSSIAN_LAYER)) {
        start_freeze_window();
        k_work_submit(&lang_to_eng_work);
    }
} else if (zmk_keymap_layer_active(RUSSIAN_LAYER)) {
    ...
}
```

**Pros**

- Matches release asymmetry already in tree; ~3 lines.
- Uses the same SoT as Esc macros (`&to 0` / `&to 1`).
- On Colemak: no Alt+Shift+1, no forced mod dump, no freeze (unless you keep freeze separately).
- On Russian: behavior unchanged (EN on press, RU on release).

**Cons / caveats**

- Still a **mirror**, not OS truth. Manual Win+Space desync remains possible.
- If default is RU but OS was forced to EN by something else, still “correct” for firmware intent.
- Product choice: whether to keep freeze/mod-clear on EN-base Lower (probably **no** — not needed without a lang chord).

**OS requirement:** keep absolute Alt+Shift+1/2 (or change both macros + C to match). Do not use bare Alt+Shift toggle.

**Effort:** tiny. **Risk:** low. First thing to ship.

---

### Rank 2 — Explicit firmware lang state (enum), not only `layer_active(1)`

Maintain `atomic` / static `enum { LANG_EN, LANG_RU }` updated by:

- `macro_to_eng` / `macro_to_rus` (or listeners on `&to 0` / `&to 1`)
- `lang_switch_freeze` itself (set EN on temporary switch, restore RU on release)
- optional: Game/`&to 0` paths that currently abandon RU (`todo.md`: Scroll `&to 0` does not restore RU)

Press Lower/Raise: emit EN chord **only if state == LANG_RU**.

**Pros**

- Clearer than “is layer 1 in the active set?” when Mouse/CtrlColemak/Fn stacks get weird.
- Can log/assert desync between state and default layer.

**Cons**

- More code paths to keep in sync; easy to forget Game/Studio/`&to`.
- Still not OS truth.

**When:** if Rank 1 mis-fires under Mouse/`&trans`/Game after testing. Otherwise YAGNI.

---

### Rank 3 — Strengthen absolute OS hotkeys (host config + docs)

No firmware change beyond Rank 1, but document / verify:

| OS | Absolute mechanism |
|----|--------------------|
| Windows | Per-layout Input language hot keys → Alt+Shift+1 EN, Alt+Shift+2 RU; disable cycle Alt+Shift if it steals chords |
| GNOME | Custom shortcuts → Shyriiwook/D-Bus activate `us`/`ru` (or equivalent), **not** “next input source” |
| X11 non-GNOME | `setxkbmap` via custom shortcut scripts |

**Pros:** makes Rank 1 chords idempotent and safe.  
**Cons:** host-dependent; multi-machine pain.  
**Effort:** docs + user settings. Do in parallel with Rank 1.

---

### Rank 4 — Unify EN/RU emission (one helper / one macro style)

Today Esc uses multi-step macros; Lower/Raise uses `LA(LS(Nn))` one-shot. Unify timing (`wait-ms`, separate mod reports — already `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT=y` on dongle) so OS always sees the same sequence.

**Pros:** fewer “works on Esc, flaky on Lower” bugs.  
**Cons:** doesn’t by itself fix unconditional press.  
**When:** after Rank 1 if OS sometimes misses freeze-path chords.

---

### Rank 5 — Host companion + Raw HID (true OS sync)

Pattern from ZMK#1716 + [zzeneg/zmk-raw-hid](https://github.com/zzeneg/zmk-raw-hid) + host app (layout change → notify keyboard; or keyboard requests “set layout”).

**Pros:** firmware can know real OS lang; can refuse chords when already EN at OS level; can heal desync.  
**Cons:** Windows service + BT/USB Raw HID on dongle; out of AGENTS.md “local firmware only” simplicity; large scope.  
**When:** only if desync from external lang switches becomes a real pain.

Related host-only tools (do not talk to ZMK layers): [polykeys](https://github.com/0xJohnnyboy/polykeys), [keyboard-layout-switcher](https://github.com/Gaeritag/keyboard-layout-switcher) — switch layout on device connect, not on Lower.

---

### Rank 6 — Avoid OS lang entirely for Lower/Raise

Emit symbols that don’t depend on OS RU (e.g. only ASCII on Lower via keycodes that are identical under EN/RU, or Unicode compose). **Not viable** for this keymap: Lower/Raise are dense punctuation designed under **OS English** while RU base stays for letters; Cyrillic OS layout remaps many “symbol” positions. Current design (temp EN) is correct; just don’t temp-EN when already EN.

---

### Anti-patterns (do not)

| Idea | Why not |
|------|---------|
| Bare Alt+Shift / Win+Space as “switch” | Toggle/cycle → desync with layers |
| Rely on HID country code / fictional language report | Ignored by hosts |
| Copy `zmk-layout-shift` as “lang switch” | Wrong problem (keycode remap) |
| Sleep/sync OS lang via Zephyr without host agent | Impossible over standard HID |
| GitHub Actions / companion in CI | Out of repo scope (local-only) |

---

## Recommended plan

1. **Implement Rank 1** in `lang_switch_freeze.c`: gate press-time `lang_to_eng_work` on `zmk_keymap_layer_active(RUSSIAN_LAYER)`. Prefer **no** freeze when skipping the chord.
2. **Keep** release-time RU restore as-is.
3. **Verify Windows** absolute hotkeys Alt+Shift+1/2 (Rank 3); disable conflicting cycle shortcut if needed.
4. Hardware matrix:
   - Colemak + Lower/Raise: **no** lang HID, symbols OK, mods not cleared spuriously.
   - Russian + Lower/Raise: EN on press, RU on release, symbols OK (existing MVP).
   - Russian + Mouse + Lower via `&trans`: still EN↔RU around hold.
   - Esc hold EN/RU: unchanged.
   - `ru_ctrl`: still no OS chord.
5. Only escalate to Rank 2/4/5 if hardware shows edge cases.

---

## File / config map

| Piece | Path |
|-------|------|
| Bug location | `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c` (`ev->state` branch ~L72–74) |
| Module Kconfig | `zmk_extra_modules/lang_switch_freeze/Kconfig` (+ duplicate in `boards/shields/charybdis/Kconfig.defconfig`) |
| Enable on dongle | `boards/shields/charybdis/charybdis_dongle.conf` |
| Build wiring | `boards/shields/charybdis/CMakeLists.txt` |
| Esc EN/RU macros | `config/behaviors/behavior_esc_layer_switch.dtsi` |
| Layer indices | `config/charybdis.keymap` (`COLEMAK 0`, `RUSSIAN 1`, `LOWER 3`, `RAISE 4`) |
| RU Ctrl (no OS) | `config/behaviors/behavior_ru_ctrl.dtsi` |
| Product notes | `todo.md` (Lower floating symbols), `todo-priority.md` |

---

## Sources

### In-repo

- `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c`
- `config/behaviors/behavior_esc_layer_switch.dtsi`
- `config/charybdis.keymap`
- `config/behaviors/behavior_ru_ctrl.dtsi`
- `boards/shields/charybdis/charybdis_dongle.conf`
- `todo.md`, `todo-priority.md`, `AGENTS.md`

### Upstream / primary-ish

- [zmkfirmware/zmk#1716](https://github.com/zmkfirmware/zmk/issues/1716) — no OS input-source feedback in ZMK without companion
- [ZMK System Configuration (HID indicators)](https://zmk.dev/docs/config/system)
- [zzeneg/zmk-raw-hid](https://github.com/zzeneg/zmk-raw-hid) — bidirectional host channel pattern
- [kot149/zmk-layout-shift](https://github.com/kot149/zmk-layout-shift) — keycode remap, not OS lang
- [USB HID / bCountryCode limitations](https://stackoverflow.com/questions/39388141/send-language-layout-from-usb-hid-keyboard)
- [Windows per-language input hot keys](https://www.digitalcitizen.life/change-keyboard-language-shortcut-windows-11/)
- [Microsoft Q&A: absolute hotkeys vs Alt+Shift cycle](https://learn.microsoft.com/en-us/answers/questions/4124976/exclude-specific-keyboard-layourt-from-shortcut)
- [GNOME absolute layout via Shyriiwook](https://github.com/madhead/shyriiwook), [write-up](https://madhead.me/posts/shyriiwook/)

---

## Bottom line

Firmware tracks **ZMK layers as a language mirror**, not real OS language. Lower/Raise already restore RU conditionally; press always forces EN — that’s the bug. Gate the press chord on `zmk_keymap_layer_active(1)`, keep absolute OS hotkeys (not toggles), and only invest in Raw-HID OS sync if manual desync becomes painful.
