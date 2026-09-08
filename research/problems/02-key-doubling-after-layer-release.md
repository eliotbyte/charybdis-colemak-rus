# Key doubling after Lower/Raise release (Colemak S/R)

**Status:** research only — no firmware edits  
**Date:** 2026-09-07  
**Repo:** `charybdis-colemak-rus`  
**Related:** [`04-lang-switch-key-buffer-replay.md`](04-lang-switch-key-buffer-replay.md), [`05-conditional-lang-switch-only-ru.md`](05-conditional-lang-switch-only-ru.md), [`01-blender-linux-exclamation-at.md`](01-blender-linux-exclamation-at.md), `todo.md` / `todo-priority.md` (Lower «капризничает», freeze timers)

---

## 1. Problem

After **exiting** Lower or Raise (momentary `&mo`), the next typed letters sometimes **duplicate**. User report: most often English Colemak **S** and **R** (possibly those finger positions / home-row labels). Feels like sticky key, OS autorepeat, or a ghost extra edge — not a slow intentional double-tap.

Scope for this note: firmware/keymap evidence + upstream ZMK races that can produce that feel. Not fixing code here.

---

## 2. Verdict (short)

**Most likely firmware cause in *this* repo:** `lang_switch_freeze` on the dongle.

It **permanently drops** `zmk_position_state_changed` events for ~50 ms around Lower/Raise (always on press; on release when ZMK Russian is active). External modules run **before** the keymap ([ZMK Events](https://zmk.dev/docs/development/events)). A press that bubbles and a matching release that is `HANDLED` (or the reverse) desyncs behavior vs HID → **stuck key → host autorepeat**, which reads as “ss” / “rr” / sticky ghost.

**Why S/R specifically:** Colemak home-row positions **14 = R**, **15 = S** (ring/middle), same left half as Lower thumb **37**. Highest-probability rollover targets when the left thumb leaves Lower. On Lower those positions are **LEFT / DOWN** (not letters) — so a mid-layer roll + freeze is especially messy.

**Not primary:** sticky keys / mod-morph (absent from keymap). Hold-tap races are secondary (Esc-lang `&to_*`, Lower `&hold` symbols). Split left↔right timing is secondary for S/R+Lower (same half); more relevant for Raise (right) + S/R (left).

**Best fix for this codebase:** harden `lang_switch_freeze` (paired quarantine or replay + real combo timing). Quick A/B: gate EN chord/freeze on RU only ([05](05-conditional-lang-switch-only-ru.md)) and/or raise `FREEZE_MS` while logging.

---

## 3. Evidence from this repo

### 3.1 Lower / Raise bindings

From `config/charybdis.keymap`:

| Layer | Thumb | Binding |
|-------|-------|---------|
| Colemak / Russian | left inner | `&mo LOWER` (pos **37**) |
| Colemak / Russian | right outer | `&mo RAISE` (pos **40**) |

No `&lt`, no sticky layer, no `&sk`. Layer exit is plain momentary release.

Colemak home row (left):

```text
pos 12–17: LSHFT  A  R  S  T  D
                 ↑  ↑
                14 15
```

Lower at those positions:

```text
pos 12–17: LSHFT  HOME  LEFT  DOWN  RIGHT  END
```

Raise at those positions:

```text
pos 12–17: LSHFT  none  F4  F5  F6  F11
```

So S/R are **not** the same HID usages as the Lower/Raise keys under the same fingers. Doubling is not “same keycode rolled across layers” in the sense of [zmk#1076 / pre-release PR #1828](https://github.com/zmkfirmware/zmk/pull/1828); it is positional / timing.

Lower **right** hand is full of `&hold` (tap-preferred, 200 ms) from `behavior_esc_layer_switch.dtsi`. That can race on the *symbol* hand; it does not map S/R on the left.

### 3.2 No sticky / mod-morph

Grep of `config/`: no `&sk`, no sticky-key, no mod-morph. Upstream sticky/hold-tap double-tap docs ([hold-tap](https://zmk.dev/docs/keymaps/behaviors/hold-tap), [sticky-key](https://zmk.dev/docs/keymaps/behaviors/sticky-key), [zmk#3279](https://github.com/zmkfirmware/zmk/issues/3279)) are background only.

Hold-taps that *do* exist:

| Behavior | Role | Flavor / term |
|----------|------|----------------|
| `&to_rus` / `&to_eng` | Esc-adjacent lang switch | tap-preferred, 200 ms |
| `&hold` | dual symbols on Lower (and some RU keys) | tap-preferred, 200 ms |
| `&lt FUNCTION ESCAPE` | corner Fn | default `&lt` |

### 3.3 `lang_switch_freeze` (central suspect)

| Piece | Path |
|-------|------|
| Logic | `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c` |
| Kconfig | module `Kconfig` + `boards/shields/charybdis/Kconfig.defconfig` |
| Enable | `boards/shields/charybdis/charybdis_dongle.conf` → `CONFIG_ZMK_LANG_SWITCH_FREEZE=y` |
| Build | `boards/shields/charybdis/CMakeLists.txt` (dongle library) |

Control flow (same as [04](04-lang-switch-key-buffer-replay.md) / [05](05-conditional-lang-switch-only-ru.md)):

```text
position event
 ├─ pos ∈ {37, 40}
 │   ├─ press  → freeze(FREEZE_MS); submit lang_to_eng_work   # ALWAYS today
 │   └─ release ∧ layer_active(RUSSIAN=1)
 │              → freeze(FREEZE_MS); submit lang_to_rus_work
 │   └─ always BUBBLE  (&mo still runs)
 └─ else ∧ frozen → HANDLED   # DROP — never reaches keymap / hold-tap
 └─ else → BUBBLE
```

Work item body:

1. `release_all_modifiers()` — synthetic **release** for all L/R Shift/Ctrl/Alt/GUI via `raise_zmk_keycode_state_changed_from_encoded(..., false, …)` (even if not pressed).
2. `k_msleep(5)` — hardcoded (ignores `CONFIG_ZMK_LANG_SWITCH_COMBO_MS`).
3. Instant tap `LA(LS(N1))` / `LA(LS(N2))` — press then release in the same function with **no** tap/wait pacing.

| Kconfig | Default | Used in `.c`? |
|---------|---------|----------------|
| `ZMK_LANG_SWITCH_FREEZE_MS` | 50 | yes |
| `ZMK_LANG_SWITCH_COMBO_MS` | 35 | **no** |

Dongle also has `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT=y` (documented in `todo.md` for mod ordering around lang switch).

### 3.4 Esc-hold path (contrast)

`behavior_esc_layer_switch.dtsi`: release mods → wait 30 ms → press Alt+Shift → tap N1/N2 → release. **No** position freeze. Same OS intent, safer pacing, different report shape than `LA(LS(Nn))`.

### 3.5 Split topology (S/R + Lower)

Dongle = BLE central; left/right = peripherals. Layer state lives on central ([split docs](https://zmk.dev/docs/features/split-keyboards)).

| Keys | Half |
|------|------|
| Lower (37), R (14), S (15) | **left** |
| Raise (40) | **right** |

So “Lower release → immediate S/R” is **same-peripheral** ordering (matrix scan order), not the classic cross-half race ([zmk#1633](https://github.com/zmkfirmware/zmk/issues/1633), [zmk#3200](https://github.com/zmkfirmware/zmk/issues/3200)). Raise → S/R **is** cross-half: layer deactivate (right event) vs letter (left event) can reorder on the central.

### 3.6 Product notes already pointing here

- `todo.md`: freeze MVP “ок”, but timers may still twitch; replay not done.
- `todo-priority.md` §2: if Lower still misbehaves → tune `ZMK_LANG_SWITCH_FREEZE_MS`; optional replay vs drop.

---

## 4. External research (primary sources)

### 4.1 Module listener priority + `HANDLED`

[ZMK Events](https://zmk.dev/docs/development/events) / [`event_manager.c`](https://github.com/zmkfirmware/zmk/blob/main/app/src/event_manager.c):

- `ZMK_EV_EVENT_HANDLED` → stop propagation; later listeners (keymap, hold-tap) **never see** the event.
- External modules linking into `app` are ordered **before** in-tree ZMK listeners.
- Docs warn: modules must not handle/capture events that ZMK behaviors need **without releasing them later**.

`lang_switch_freeze` **drops** events by design (no `CAPTURED`, no re-raise). That is a known trade-off vs [04](04-lang-switch-key-buffer-replay.md).

### 4.2 Layer deactivate vs held key

Historical bug [zmk#67](https://github.com/zmkfirmware/zmk/issues/67): release after `&mo` deactivate invoked the **base** binding. Fixed by remembering the layer that handled the press ([PR #79](https://github.com/zmkfirmware/zmk/pull/79)). Current ZMK should keep Lower’s LEFT/DOWN (or Raise’s F4/F5) until physical release — **unless** our freeze swallows that release.

Related oddities: [zmk#2526](https://github.com/zmkfirmware/zmk/issues/2526) (keydown+keyup collapsing with `&mo`), [zmk#2847](https://github.com/zmkfirmware/zmk/issues/2847) (mods stuck across nested layer macros).

### 4.3 HID coalescing / mod release / “repeat-like” output

- Macros docs: for HID sequences, **wait/tap ≥ ~30 ms** to avoid BLE/HID reordering ([macros](https://zmk.dev/docs/keymaps/behaviors/macros)). Freeze combo uses ~0 ms between press and release of `LA(LS(Nn))`, plus only 5 ms after mod spray. Esc macros use 5 ms tap/wait after a 30 ms pause — still aggressive vs 30 ms guidance, but structured.
- [`CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT`](https://zmk.dev/docs/config/system): send non-mod release **before** clearing mods ([`hid_listener.c`](https://github.com/zmkfirmware/zmk/blob/main/app/src/hid_listener.c)). Helps hosts that mis-order releases; already `y` on dongle.
- Same file: if a usage is pressed while already down → **pre-release then press** (extra HID edges). Host can show an extra character / restart repeat. Comment in release path: premature implicit-mod clear can make a held key **autorepeat** (`Bbbbbbbb`-style).

`release_all_modifiers()` + instant `LA(LS(N2))` on Russian **layer exit** is exactly the window where synthetic mod/key edges and real letter presses collide.

### 4.4 Debounce / chatter

Default matrix debounce ~5 ms ([kscan config](https://zmk.dev/docs/config/kscan)). This repo does **not** override `CONFIG_ZMK_KSCAN_DEBOUNCE_*`. Thumb release → home-row bounce is a plausible **mechanical** contributor for S/R; treat as A/B after firmware quarantine is fixed or disabled.

---

## 5. Why S and R (mapping)

| Factor | Detail |
|--------|--------|
| Positions | Colemak **R=14**, **S=15** — home row, strongest left fingers after thumb |
| Same half as Lower | Rollover “thumb up, finger down” lands on 14/15 first |
| Lower under those fingers | **LEFT / DOWN** — nav keys, not R/S; layer exit + immediate letter is a hard transition |
| Raise under those fingers | **F4 / F5** — if cross-split race fires layer key then letter, user would more often see F-keys or wrong glyphs than “SS”; still worth testing Raise-only |
| Frequency | R/S are very common in EN; selection bias |
| Language label | “English Colemak S/R” may mean (a) Colemak base layer, or (b) physical keys after OS was forced EN during Lower. On RU base, after release, OS returns to RU ([freeze release path](../../zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c)) — confirm which base layer reproduces |

**Hypothesis rank for “SS/RR after exit”:**

1. **Freeze asymmetry (stuck → OS repeat)** around Russian **release** freeze, or press freeze if rolling into Lower with a letter already down.
2. **Synthetic lang HID** (`LA(LS(N2))` / mod spray) interacting with `SEPARATE_MOD_RELEASE` / pre-release — extra edges; see also digit leaks in [01](01-blender-linux-exclamation-at.md) (`!`/`@` from N1/N2).
3. **Mechanical bounce** of 14/15 when unloading left thumb.
4. **Raise + cross-split** reordering (less specific to S/R letters).
5. **`&hold` / Esc hold-tap** — weak for left-home S/R.

---

## 6. Failure modes (concrete timelines)

### A. Swallowed release → stuck → autorepeat (best match to “sticky/repeat”)

```text
t0  key 14/15 DOWN reaches keymap (letter on Colemak, or LEFT/DOWN on Lower)
t1  Lower/Raise edge starts freeze (press always; release if RU)
t2  matching UP arrives while frozen → HANDLED → keymap never releases
t3  HID usage still down → OS autorepeat → "rrrr" / "ssss" / stuck nav
```

Orphan **press** during freeze (no HID down) then UP after unfreeze is usually a no-op for `&kp` — lost key, not double. Doubling/repeat needs **down without up** (or HID pre-release churn).

### B. Russian release: second freeze + OS RU chord

```text
t0  release Lower/Raise, layer_active(RU)
t1  freeze 50ms + release_all_mods + sleep 5 + tap LA(LS(N2))
t2  immediate home-row letter overlaps synthetic HID
t3  odd host parsing / extra edges / layout mid-switch glyphs
```

On **Colemak** base, release does **not** start freeze or RU chord — if the bug reproduces on Colemak-only, prefer A on **press** freeze, mechanical bounce, or Raise cross-split — not release-time lang restore.

### C. Unconditional EN on every Lower press ([05](05-conditional-lang-switch-only-ru.md))

Even when already EN/Colemak: freeze + mod clear + Alt+Shift+1. Extra quarantine windows → more chances for A. Gating press to RU-only reduces exposure.

---

## 7. Solution variants

### Variant 1 — Paired quarantine (fix drop) — **recommended first**

Keep drop (small change), but track positions masked during freeze:

- On `HANDLED` **press**: remember position.
- On matching **release** while frozen **or** after unfreeze: swallow until pair complete (or force-release HID if press was delivered before freeze).
- Optionally: on freeze **start**, for any position already down, either (i) don’t freeze that position’s release, or (ii) explicitly release its active binding before quarantine.

**Files:** `lang_switch_freeze.c` (+ maybe Kconfig for policy).  
**Pros:** targets stuck-key doubles; keeps MVP drop model.  
**Cons:** still loses intended taps during window (unless combined with 2).

### Variant 2 — Replay queue (product-complete)

Capture instead of drop; replay after combo + margin. Spec’d in [04](04-lang-switch-key-buffer-replay.md).

**Files:** `lang_switch_freeze.c`, Kconfig, possibly `charybdis_dongle.conf`.  
**Pros:** no lost keys; can unify timing.  
**Cons:** larger design; must not reorder with `&mo` / hold-tap; `todo-priority` says don’t mix casually with drop tuning.

### Variant 3 — Timing / gating only (fast A/B)

1. Gate EN chord + freeze on press with `zmk_keymap_layer_active(RUSSIAN)` ([05](05-conditional-lang-switch-only-ru.md)).
2. Honor `CONFIG_ZMK_LANG_SWITCH_COMBO_MS` (and/or ≥30 ms) in `tap_lang_combo`; align with Esc macros.
3. Extend freeze to **cover combo end + margin** (start freeze when work starts, end when work finishes + N ms), not a blind 50 ms from thumb edge.
4. Override in `charybdis_dongle.conf`: e.g. `CONFIG_ZMK_LANG_SWITCH_FREEZE_MS=80` (or higher) as experiment.

**Files:** `lang_switch_freeze.c`, `charybdis_dongle.conf`, optionally `Kconfig.defconfig`.  
**Pros:** matches existing todo; low risk.  
**Cons:** does not by itself fix press/release asymmetry.

### Variant 4 — Debounce / mechanical differential

Bump `CONFIG_ZMK_KSCAN_DEBOUNCE_PRESS_MS` / `_RELEASE_MS` to 10 on halves ([kscan](https://zmk.dev/docs/config/kscan)). Only after firmware A/B, or if doubling happens with freeze disabled.

**Files:** `config/charybdis_left.conf`, `config/charybdis_right.conf` (or shared).  
**Pros:** cheap.  
**Cons:** masks bounce only; won’t fix swallowed releases.

### Out of scope / weak here

- Enabling sticky-key workarounds / `hold-while-undecided-linger` — no sticky mods on these keys.
- Blindly disabling `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT` — it was added for lang/mod correctness; A/B only with USB HID logging.

---

## 8. Recommendation

**Ship Variant 1 + the gating/timing pieces of Variant 3** in `lang_switch_freeze`; keep Variant 2 as the follow-up if lost symbols during the window still annoy ([04](04-lang-switch-key-buffer-replay.md)).

Rationale:

- Symptom shape (“sticky / repeat / ghost **after** layer exit”) matches **desynced position edges** and **synthetic HID on RU release**, not sticky-key or S/R keycode aliasing on Lower.
- Code already owns quarantine; `COMBO_MS` is dead; press path over-fires on Colemak ([05](05-conditional-lang-switch-only-ru.md)).
- Replay is the right long-term UX but is a separate design fork per `todo-priority.md`.

### Suggested validation order (hardware)

1. Reproduce with HID inspector (Keyboard Tester / `evtest` / Wireshark USB): look for **down without up**, or down-up-down within one physical press.
2. A/B: `CONFIG_ZMK_LANG_SWITCH_FREEZE=n` on dongle — if doubles vanish, freeze is causal.
3. A/B: Colemak-only vs Russian-only — if only RU, release-time `lang_to_rus` + freeze is implicated.
4. A/B: Lower-only vs Raise-only — Raise implicates cross-split more.
5. Then implement paired quarantine + RU-only press gate + real combo delays; retest.

---

## 9. Exact files to touch (when implementing)

| File | Change |
|------|--------|
| `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c` | Paired drop / force-release; use `COMBO_MS`; optional freeze end tied to work completion; gate EN on RU |
| `zmk_extra_modules/lang_switch_freeze/Kconfig` | Document real meaning of `COMBO_MS` / new options |
| `boards/shields/charybdis/Kconfig.defconfig` | Keep defaults in sync |
| `boards/shields/charybdis/charybdis_dongle.conf` | Tune `FREEZE_MS` / experiment flags; already has freeze + `HID_SEPARATE_MOD_RELEASE_REPORT` |
| `boards/shields/charybdis/CMakeLists.txt` | Only if splitting sources |
| `config/behaviors/behavior_esc_layer_switch.dtsi` | Optional: unify OS chord encoding/timing with freeze module |
| `config/charybdis.keymap` | Only if changing `&mo` / positions (unlikely for this bug) |
| `config/charybdis_left.conf` / `_right.conf` | Debounce A/B only |
| `todo.md` / `todo-priority.md` | Mark outcome after hardware confirm |

**Do not** add CI workflows; build with `.\build.ps1 verify` / `.\build.ps1` per `AGENTS.md`.

---

## 10. Sources

### Repo

- `config/charybdis.keymap`
- `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c`
- `zmk_extra_modules/lang_switch_freeze/Kconfig`
- `boards/shields/charybdis/charybdis_dongle.conf`
- `boards/shields/charybdis/Kconfig.defconfig`
- `boards/shields/charybdis/CMakeLists.txt`
- `config/behaviors/behavior_esc_layer_switch.dtsi`
- `todo.md`, `todo-priority.md`
- Sibling research: [01](01-blender-linux-exclamation-at.md), [04](04-lang-switch-key-buffer-replay.md), [05](05-conditional-lang-switch-only-ru.md)

### Upstream

- [ZMK Events](https://zmk.dev/docs/development/events) — `HANDLED` / module order  
- [event_manager.c](https://github.com/zmkfirmware/zmk/blob/main/app/src/event_manager.c)  
- [hid_listener.c](https://github.com/zmkfirmware/zmk/blob/main/app/src/hid_listener.c) — separate mod release, pre-release, implicit-mod repeat comment  
- [System config — `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT`](https://zmk.dev/docs/config/system)  
- [Macros — ≥30 ms HID pacing](https://zmk.dev/docs/keymaps/behaviors/macros)  
- [Hold-tap](https://zmk.dev/docs/keymaps/behaviors/hold-tap) / [Sticky key](https://zmk.dev/docs/keymaps/behaviors/sticky-key)  
- [Split keyboards](https://zmk.dev/docs/features/split-keyboards)  
- [Kscan debounce](https://zmk.dev/docs/config/kscan)  
- [zmk#67](https://github.com/zmkfirmware/zmk/issues/67) layer release binding  
- [zmk#2526](https://github.com/zmkfirmware/zmk/issues/2526), [zmk#2847](https://github.com/zmkfirmware/zmk/issues/2847), [zmk#3200](https://github.com/zmkfirmware/zmk/issues/3200), [zmk#1633](https://github.com/zmkfirmware/zmk/issues/1633)  
- [PR #1828](https://github.com/zmkfirmware/zmk/pull/1828) HID pre-release on re-press  
