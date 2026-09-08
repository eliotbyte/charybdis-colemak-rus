# Key doubling while plain typing (S / C / R burst)

**Status:** research only — no firmware edits  
**Date:** 2026-09-08  
**Repo:** `charybdis-colemak-rus`  
**Related:** [`02-key-doubling-after-layer-release.md`](02-key-doubling-after-layer-release.md) (after Lower/Raise — **different trigger**), [`04`](04-lang-switch-key-buffer-replay.md), `todo-priority.md` (lang freeze already gated + paired quarantine)

---

## 1. Problem

User types normally (not necessarily exiting Lower/Raise). Keys such as **S / C / R** sometimes emit **2–3 characters**. Feels like the firmware/HID sends them **very fast / almost simultaneous** — discrete burst, not classic OS autorepeat of a stuck key (which is: one glyph → ~RepeatDelay → stream).

Scope: distinguish from [02](02-key-doubling-after-layer-release.md), rank causes that match **burst of complete taps**, propose A/B.

---

## 2. Verdict (short)

**Best match for “2–3 almost at once while just typing”:** mechanical **contact bounce / hotswap chatter** on left-half switches (positions **R=14, S=15, C=27** on Colemak), with stock ZMK debounce **5 ms** and **no** override in this repo. Official ZMK debounce docs call out exactly this symptom + hotswap sockets.

**Amplifier (same shape):** bounce that produces an extra press while HID still thinks the usage is down → [`hid_listener` pre-release then press](https://github.com/zmkfirmware/zmk/pull/1828) → host sees an extra edge pair inside one physical actuation.

**Weaker for this report (still real elsewhere):** `lang_switch_freeze` — current code has RU-only arm + paired quarantine; plain Colemak typing without thumb Lower/Raise should not freeze. More relevant if doubles cluster on **Russian** base with accidental Lower graze ≥ `THUMB_ARM_MS` (30 ms). Symptom of freeze bugs is more often **lost** keys or **stuck → autorepeat**, not a tight 2–3 burst.

**Not primary:** combos (R/S/C not in any combo), sticky keys (absent), `&hold` on Colemak R/S/C (plain `&kp`), auto_mouse (only extends timer / bubbles).

---

## 3. Positions (this keymap)

3×6 Charybdis layout (`charybdis.dtsi` position map + `charybdis.keymap`):

| Letter (Colemak) | Pos | Matrix role |
|------------------|----:|-------------|
| **R** | 14 | home row, left |
| **S** | 15 | home row, left |
| **C** | 27 | bottom row, left |
| Lower thumb | 37 | same half |
| Raise thumb | 40 | right half |

Colemak bindings: all three are plain `&kp` (no hold-tap).

Russian layer: physical 14/15/27 become **S / D / C** (`&kp`), still plain key-press. Naming “s/c/r” may mean Colemak letters **or** those finger positions — both sit on the **left peripheral**.

Combos (`timeout-ms=20`): positions `20 24`, `25 29`, `37 38`, `1 2`, `2 3`, `11 12`, `0 4` — **none** include 14/15/27.

---

## 4. Symptom shape → diagnostic fork

| Shape | Likely cause family |
|-------|---------------------|
| Glyphs appear **together** (no ~300–500 ms gap); HID shows `↓↑↓↑` or `↓↑↓↑↓↑` within ~5–40 ms | Chatter / bounce / pre-release churn |
| One glyph, pause, then `ssss…` until release/reset | Stuck position / lost UP (split #281 class, or freeze swallow release — mitigated by paired quarantine) |
| Only after Lower/Raise | [02](02-key-doubling-after-layer-release.md) / lang chord HID |
| Only on Russian + thumb rest on Lower | freeze arm path (`THUMB_ARM_MS`) |

User wording maps to **row 1**.

---

## 5. Hypotheses (ranked)

### H1 — Contact bounce / hotswap chatter (highest for “just typing”)

**Mechanism:** switch or socket opens/closes more than once per intended press. ZMK per-key debounce requires **stable** press/release for `CONFIG_ZMK_KSCAN_DEBOUNCE_*_MS` (default **5**). Multiple stable windows → multiple full press/release cycles → host gets 2–3 discrete characters in a burst.

**Evidence in repo:**

- `charybdis_left.overlay` / `charybdis_right.overlay`: `zmk,kscan-gpio-matrix`, **no** `debounce-press-ms` / `debounce-release-ms`.
- No `CONFIG_ZMK_KSCAN_DEBOUNCE_*` in `*.conf`.
- R/S/C are all **left half** — one MCU, same matrix; selective keys ⇒ switch/socket quality or local PCB/noise more than global firmware logic.

**Primary source:** [Debouncing | ZMK](https://zmk.dev/docs/features/debouncing) — *“single key press registering multiple inputs”* → raise debounce; check hotswap sockets.

**Fits:** key-specific, burst, no layer needed.  
**Doesn’t need:** lang freeze, combos, hold-tap.

### H2 — Bounce + HID pre-release (amplifier)

**Mechanism:** if a second `keycode pressed` arrives while that usage is still marked pressed in HID, ZMK **releases then presses** and sends an extra report ([PR #1828](https://github.com/zmkfirmware/zmk/pull/1828), [`hid_listener.c`](https://github.com/zmkfirmware/zmk/blob/main/app/src/hid_listener.c)). That can turn messy bounce into an **extra visible character** even when the behavior layer thought it was one hold.

**Fits:** “almost simultaneous” doubles/triples.  
**Test:** HID inspector — look for down/up/down with tiny gaps on one usage.

### H3 — `lang_switch_freeze` residual (conditional)

**Current code** (`lang_switch_freeze.c`, post-quarantine / RU gate):

- EN chord + freeze only if `zmk_keymap_layer_active(RUSSIAN)` and Lower/Raise held ≥ `THUMB_ARM_MS` (30 ms).
- Grazes cancel before arm.
- Frozen presses → `HANDLED` + bit in `quarantined_presses`; matching release always swallowed; **already-held** release never swallowed.
- Combo pacing uses `COMBO_MS`; freeze spans `COMBO_HOLD_MS` then `FREEZE_MS` after combo.

**How it could still bite while “typing”:**

1. RU base, thumb rests on Lower ≥30 ms during a word → freeze window → drops mid-roll keys (usually **missing** letters).
2. Edge cases around quarantine bit clear-on-repress (stale bit) — more **stuck** than burst-double if buggy.
3. Synthetic `Alt+Shift+N1/N2` overlapping a letter — wrong glyph / mod edges ([01](01-blender-linux-exclamation-at.md)), not typically `sss`.

**Fits poorly** for Colemak-only plain typing with thumbs clear of Lower/Raise.  
**Fits better** if user self-report mixes “plain typing” with light Lower use on RU.

A/B: `CONFIG_ZMK_LANG_SWITCH_FREEZE=n` on dongle; or Colemak-only session with thumbs off layers.

### H4 — Split BLE lost/duplicated edges (low for burst-2–3)

Historical peripheral stuck keys from dropped releases ([zmk#281](https://github.com/zmkfirmware/zmk/issues/281)); disconnect release fix ([PR #1340](https://github.com/zmkfirmware/zmk/pull/1340)). Classic symptom is **infinite autorepeat**, not a tidy 2–3-tap burst. Worth keeping if HID shows long hold without user holding.

R/S/C are left peripheral → all go through BLE to dongle central. Global RF issues would hit many left keys, not only three — unless those switches chatter and BLE just faithfully forwards chatter.

### H5 — Soft bottom-out / finger bounce (user/mech)

Home-row R/S and bottom C get hit hard in English; slight rebound can re-trigger after debounce window. Feels firmware-like. Same A/B as H1 (higher release debounce helps both chatter and light rebound).

### H6 — OS / IME / filter keys (low)

Windows Filter Keys, sticky keys, or layout switch mid-glyph usually don’t pick **only** S/C/R. Rule out with HID log **before** OS text field (Keyboard Tester / Wireshark USB on dongle).

### H7 — Hold-tap / combo / auto_mouse (weak)

- Colemak R/S/C = `&kp` only.
- Combos don’t include those positions.
- `auto_mouse_layer` listens to keycodes, bubbles, does not re-inject presses.

---

## 6. Contrast with research 02

| | [02](02-key-doubling-after-layer-release.md) | This note (07) |
|--|-----------------------------------------------|-----------------|
| Trigger | After Lower/Raise release | Plain typing |
| Top suspect then | freeze drop asymmetry → stuck → OS repeat | matrix chatter / debounce |
| Code since 02 | RU gate, `THUMB_ARM_MS`, paired quarantine, sequential combo | same — reduces 02-class bugs |
| Feel | sticky / repeat | simultaneous burst |

If hardware still doubles **only** after layers → revisit 02 + freeze timers. If doubles during idle Colemak home-row → prioritize H1/H2.

---

## 7. Hardware A/B order

1. **HID capture** (Keyboard Tester / `evtest` / USBPcap): one intentional tap on S when it doubles.  
   - `↓S ↑S ↓S ↑S` within tens of ms → H1/H2.  
   - `↓S` then long hold / OS repeat → stuck path (H3/H4).
2. **Debounce A/B** on left (and optionally right) conf:
   ```ini
   CONFIG_ZMK_KSCAN_DEBOUNCE_PRESS_MS=10
   CONFIG_ZMK_KSCAN_DEBOUNCE_RELEASE_MS=15
   ```
   If doubles vanish → H1/H5 confirmed. Start at 10/10 if latency bothers.
3. **Swap switches / reseat hotswap** for pos 14, 15, 27 — ZMK docs’ mechanical check.
4. **Freeze off:** `CONFIG_ZMK_LANG_SWITCH_FREEZE=n` — if unchanged, freeze not causal for this bug.
5. **Colemak-only vs RU-only** long typing sessions — RU-only doubles implicate H3 more.
6. Optional: flash left half as USB central briefly (if practical) to see if BLE is involved — only if 2–5 disagree.

---

## 8. Fix variants (when acting)

| # | Change | When |
|---|--------|------|
| 1 | Raise debounce on halves (`charybdis_left.conf` / `_right.conf` or `&kscan0` props) | H1/H5 confirmed |
| 2 | Reseat/replace switches/sockets for 14/15/27 | key-specific after debounce helps partially |
| 3 | Keep freeze as-is; only tune if A/B #4 moves the needle | H3 |
| 4 | Don’t disable `HID_SEPARATE_MOD_RELEASE` for this bug | unrelated to letter burst |

Replay queue ([04](04-lang-switch-key-buffer-replay.md)) does **not** fix plain-typing chatter.

---

## 9. Sources

### Repo

- `config/charybdis.keymap` — bindings / combos / positions  
- `boards/shields/charybdis/charybdis.dtsi` — position map  
- `boards/shields/charybdis/charybdis_left.overlay` — kscan, no debounce props  
- `boards/shields/charybdis/charybdis_dongle.conf` — freeze on, no kscan debounce  
- `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c` — current freeze  
- `zmk_extra_modules/auto_mouse_layer/src/auto_mouse_layer.c`  
- `todo-priority.md` — quarantine/gate already shipped  
- [02](02-key-doubling-after-layer-release.md)

### Upstream

- [Debouncing](https://zmk.dev/docs/features/debouncing)  
- [PR #1828](https://github.com/zmkfirmware/zmk/pull/1828) HID pre-release  
- [`hid_listener.c`](https://github.com/zmkfirmware/zmk/blob/main/app/src/hid_listener.c)  
- [zmk#281](https://github.com/zmkfirmware/zmk/issues/281) split stuck keys  
- [PR #1340](https://github.com/zmkfirmware/zmk/pull/1340) release on disconnect  
