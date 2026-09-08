# 06 — RU Ctrl blocks mouse and Lower/Raise

**Status:** researched (no firmware edits)  
**Repo:** `charybdis-colemak-rus`  
**Symptoms (RU base):** hold `&ru_ctrl` → trackball/mouse UX dies; cannot use Lower/Raise unless Raise (or Lower) is held *before* Ctrl. Desired: Ctrl first, then Lower, and chords work.

---

## 1. What the firmware actually does

### 1.1 `&ru_ctrl`

[`config/behaviors/behavior_ru_ctrl.dtsi`](../../config/behaviors/behavior_ru_ctrl.dtsi):

```dts
ru_ctrl: ru_ctrl {
  compatible = "zmk,behavior-macro";
  bindings =
    <&macro_press &mo 9 &kp LCTRL>
  , <&macro_pause_for_release>
  , <&macro_release &kp LCTRL &mo 9>;
};
```

This is the stock ZMK **layer + modifier** pattern (`&mo` + `&kp` around `&macro_pause_for_release`), same idea as the documented `&lm` example.

Sources:

- [ZMK Macro Behavior — Layer + modifier](https://zmk.dev/docs/keymaps/behaviors/macros)
- [ZMK Momentary Layer (`&mo`)](https://zmk.dev/docs/keymaps/behaviors/layers)

Intent (also in `todo.md` / `todo-priority.md`): on **Russian** OS layout, physical keys sit on ЙЦУКЕН positions; Ctrl chords expect **Colemak letter positions**. Holding Ctrl raises `CtrlColemak` (layer 9) + `LCTRL` **without** changing OS language.

### 1.2 Layer stack (definition order = priority)

From [`config/charybdis.keymap`](../../config/charybdis.keymap):

| Index | Name | Role |
|------:|------|------|
| 0 | Colemak | EN base |
| 1 | Russian | RU base |
| 2 | Mouse | auto-mouse buttons / Scroll / Screen |
| 3 | Lower | nav / symbols |
| 4 | Raise | nums / F-keys |
| 5–8 | Scroll…Reset | pointing / util |
| **9** | **CtrlColemak** | Colemak alphas **while RU Ctrl held** |
| 10–12 | Game…Fun | game / fn |

ZMK rule (hard): **higher index wins among active layers**, regardless of activation order. Opaque bindings consume the event; only `&trans` passes down; `&none` blocks.

Sources:

- [ZMK Keymaps — Layers](https://zmk.dev/docs/keymaps)
- [ZMK Misc — Transparent / None](https://zmk.dev/docs/keymaps/behaviors/misc)
- [zmkfirmware/zmk#2382](https://github.com/zmkfirmware/zmk/issues/2382) (caksoylar: `&mo` activates the layer, but a *higher-defined* active layer still captures first)

### 1.3 `CtrlColemak` bindings (the smoking gun)

Thumbs on CtrlColemak:

```text
&trans  &trans  &kp SPACE  &kp RET  &trans
```

Alpha block is a **full opaque Colemak `&kp` map** (same shape as Colemak base), including left Ctrl slot as `&kp LCTRL`.

So with `&ru_ctrl` held:

- Active: Russian (1) + CtrlColemak (9) [+ maybe Mouse/Lower/Raise]
- Thumb Lower/Raise: `&trans` → falls through → Russian’s `&mo LOWER` / `&mo RAISE` **can activate**
- **Letter / mouse-button positions:** CtrlColemak (9) wins forever while held — Lower (3), Raise (4), Mouse (2) never show through

### 1.4 Why “Raise first, then Ctrl” works

Raise / Lower layers bind **plain** `&kp LCTRL` on the same physical key — **not** `&ru_ctrl`:

```text
# Lower / Raise bottom-left
&kp LCTRL  ...
```

Sequence Raise → Ctrl:

1. `&mo RAISE` → layer 4 up; `lang_switch_freeze` already flipped OS to EN and released mods.
2. Ctrl resolves on **Raise**, so `&kp LCTRL` only — **CtrlColemak never activates**.
3. Raise (4) stays the highest relevant layer for alphas → nums/F-keys work with Ctrl.

Sequence Ctrl → Raise:

1. `&ru_ctrl` → CtrlColemak (9) + LCTRL.
2. Thumb Raise: `&trans` → `&mo RAISE` activates Raise (4).
3. **CtrlColemak (9) > Raise (4)** → Raise content fully shadowed by Colemak letters.

Same for Lower. This matches the reported UX exactly. Not sticky-mods; not a broken `&mo`. It is **layer index precedence**.

### 1.5 Sticky mods?

No `&sk` / sticky-mod path for Ctrl in this keymap. “Sticky” feel is the momentary layer overlay + HID Ctrl held by the macro.

---

## 2. Why mouse / trackball “dies”

Two independent mechanisms; both fire when `&ru_ctrl` is held.

### 2.A Layer shadow (primary for buttons / Mouse UX)

`auto_mouse_layer.c` activates **Mouse = 2**:

```c
zmk_keymap_layer_activate(MOUSE_LAYER, false);  /* MOUSE_LAYER 2 */
```

While CtrlColemak (9) is active: **Mouse (2) < 9** → LMB/RMB (`&mkp`), `&mo SCROLL`, `&mo SCREEN` on the Mouse layer are invisible. Mouse layer can be “on” and still useless.

Hardcoded indices to keep in sync if layers move:

- [`zmk_extra_modules/auto_mouse_layer/src/auto_mouse_layer.c`](../../zmk_extra_modules/auto_mouse_layer/src/auto_mouse_layer.c) — `MOUSE_LAYER 2`, `GAME_LAYER 10`, `GAME_LOWER_LAYER 11`
- [`config/charybdis_dongle.overlay`](../../config/charybdis_dongle.overlay) — `scroller { layers = <5>; }` (Scroll)
- [`boards/shields/charybdis/split_input_common.dtsi`](../../boards/shields/charybdis/split_input_common.dtsi) — move/scroll layer lists (mostly deleted on dongle)

### 2.B `keyboard_lock` (blocks / delays Mouse *activation*)

On any keycode press while mouse inactive:

```c
atomic_set(&keyboard_lock, 1);
k_work_reschedule(&keyboard_lock_work, K_MSEC(CONFIG_ZMK_AUTO_MOUSE_KB_LOCK_MS));
```

`&ru_ctrl` presses `&kp LCTRL` → keycode event → lock for **500 ms** (default `CONFIG_ZMK_AUTO_MOUSE_KB_LOCK_MS`). While locked, `activate_mouse_fn` returns early — trackball motion does not raise Mouse.

Intent of lock (todo / comments): typing on Colemak/RU must not pop Mouse when the ball twitches. Side effect: **holding Ctrl is “typing”** for this heuristic.

### 2.C Cursor REL on dongle (likely still moves)

Dongle overlay deletes the layer-gated `move` node and attaches `&pointer_accel` globally on `&trackball_listener`. So **cursor motion HID** should still work under CtrlColemak; what dies is Mouse-layer *buttons / Scroll / Screen*.

If the user truly sees **zero cursor motion** under Ctrl, that needs a separate hardware log (unlikely from layer index alone on current dongle overlay). Most probable report meaning: “mouse mode / clicks / scroll-via-mouse-layer dead.”

Sources (local):

- `auto_mouse_layer.c` — lock + activate
- `charybdis_dongle.overlay` — global accel, Scroll `@5`
- `todo.md` — keyboard_lock semantics

---

## 3. Extra: `lang_switch_freeze` vs Ctrl-then-Lower

[`lang_switch_freeze.c`](../../zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c) on Lower/Raise **press**:

1. Freeze window (~50 ms) — drops other positions.
2. `release_all_modifiers()` — **releases LCTRL** that `&ru_ctrl` just held.
3. OS → EN via Alt+Shift+1.

On release, if Russian layer still active → OS → RU.

Effects while designing Ctrl→Lower chords:

- Host Ctrl can drop mid-chord even though the physical key is still held (macro vs host desync).
- OS language flickers EN↔RU — matches “Ctrl hold switches language slightly” if combined with Lower/Raise attempts.
- Does **not** fix layer shadowing; worsens Ctrl chord reliability on RU.

Freeze listens by **position** (37 / 40), not by which behavior won — so even `&trans` → `&mo LOWER` still triggers freeze.

---

## 4. ZMK patterns that don’t block other momentary layers

| Pattern | Works for this? | Notes |
|---------|-----------------|-------|
| Base layers low (0/1), overlays high | Required | ZMK docs: put alternate bases at lowest indices so momentary layers sit above both. CtrlColemak was placed like a “base remap” but at index **9** — treated as top overlay. |
| `&trans` on overlay thumbs | Activates nested `&mo` | Already done; **insufficient** for content keys. |
| `&mo` nested under higher opaque layer | Activates, but shadowed | #2382 |
| Official `&lm` / layer+mod macro | Same as `&ru_ctrl` | Doesn’t change precedence. |
| Conditional layers | Possible band-aid | `if-layers = <CTRL_COLEMAK LOWER>` → `then-layer` = copy of Lower **above** both. Duplicates maps; `then-layer` must be higher; don’t also `&mo` the then-layer. [Docs](https://zmk.dev/docs/keymaps/conditional-layers) |
| Reorder CtrlColemak **below** Mouse/Lower/Raise | Canonical fix | Remap still beats Russian; Lower/Mouse beat remap when active. |
| Mod-morph / per-key Ctrl morphs | No layer stack fight | Huge keymap; hard to maintain Colemak↔RU map. |

Compatible mental model for this repo:

```text
priority high → low (when all relevant layers active):
  Fun / Game overlays
  Lower / Raise / Scroll / Screen / Mouse   ← must beat CtrlColemak
  CtrlColemak                               ← must beat Russian only
  Russian / Colemak
```

---

## 5. Concrete solutions (ranked for this repo)

### Rank 1 — Reorder: `CtrlColemak` just above Russian (best)

**Change:** move `CtrlColemak` node to index **2** (immediately after Russian). Shift Mouse, Lower, Raise, Scroll, … up by one. Keep `&ru_ctrl` as `&mo CTRL_COLEMAK` + `LCTRL` (or stock `&lm`).

**Why it fixes both bugs:**

- Ctrl → Lower: Lower index > CtrlColemak → symbols/nav visible with Ctrl still held.
- Ctrl → Mouse: Mouse > CtrlColemak → buttons/Scroll/Screen visible; auto-mouse useful again.
- Ctrl alone on RU: CtrlColemak > Russian → Colemak positions for shortcuts (goal preserved).

**Must update hardcodes:**

- `#define` block in `charybdis.keymap`
- `auto_mouse_layer.c` (`MOUSE_LAYER`, Game indices)
- `charybdis_dongle.overlay` `layers = <5>` → new Scroll index
- `split_input_common.dtsi` layer defines / lists
- Kconfig defaults only if layer numbers for freeze Russian stay `1` (unchanged)

**Pros:** One structural fix; ZMK-idiomatic; no duplicate layers.  
**Cons:** Touch many index references; full smoke test (Game, Scroll snap, Studio, drawer YAML).  
**Effort:** medium.

### Rank 2 — Conditional “Ctrl+Lower” / “Ctrl+Raise” then-layers

Keep CtrlColemak at 9. Add high layers (e.g. 13/14) that are **copies** of Lower/Raise, activated via:

```dts
conditional_layers {
  compatible = "zmk,conditional-layers";
  ctrl_lower {
    if-layers = <9 3>;  /* CtrlColemak + Lower */
    then-layer = <13>;
  };
};
```

**Pros:** No reshuffle of existing indices; surgical.  
**Cons:** Duplicate Lower/Raise maps; conditional `then-layer` ownership quirks; Mouse still shadowed unless more conditionals or Mouse raised above 9; interacts worse with `lang_switch_freeze`.  
**Effort:** medium–high, fragile.

### Rank 3 — Soften auto-mouse lock for mods + transparent Mouse region on CtrlColemak

Partial / incomplete:

1. In `keycode_listener_cb`, ignore pure modifiers (`LCTRL`/`LSHFT`/…) for `keyboard_lock` so trackball can raise Mouse while Ctrl held.
2. On CtrlColemak, set right-hand Mouse positions (`&mkp`, Scroll/Screen) to `&trans` so Mouse (2) shows through **if** Mouse is active — **still fails** because Mouse (2) < CtrlColemak (9); `&trans` falls to Russian, not to a *lower* Mouse layer under a higher opaque neighbor… Actually: resolution walks **active** layers high→low. If CtrlColemak has `&trans` at MB1, next is Mouse (2) if active — **yes**, `&trans` would reach Mouse.

So: make CtrlColemak **transparent on Mouse-cluster positions** (and optionally thumbs already are) **plus** ignore mods in keyboard_lock → mouse buttons can work **without** full reorder.

**Does not fix Lower/Raise letter shadowing** unless those positions are also `&trans` — which would defeat Colemak remap on those keys when only Ctrl is held.

**Pros:** Small C + keymap diff for mouse half of the bug.  
**Cons:** Incomplete vs user ask (Lower after Ctrl); easy to miss positions.  
**Effort:** low for mouse-only.

### Rank 4 — Drop overlay layer; switch OS lang on Ctrl (or accept RU Ctrl chords)

On `&ru_ctrl` press: OS→EN (reuse freeze combo) + plain `LCTRL` on Colemak base via `&to`/`&mo` Colemak; release restores RU. Or leave RU and live with ЙЦУКЕН Ctrl chords.

**Pros:** No layer precedence war.  
**Cons:** Opposes current “OS lang unchanged” design; fights `lang_switch_freeze` / Esc macros; worse latency / drop window.  
**Effort:** medium; product tradeoff.

---

## 6. Recommended path

1. **Do Rank 1** (reorder CtrlColemak under Mouse/Lower/Raise). That is the only clean fix for both reported symptoms under ZMK’s precedence model.
2. While touching RU Ctrl UX, decide policy for **Ctrl+Lower on RU**:
   - either exclude Lower/Raise from freeze when Ctrl already held, or
   - accept EN flick for symbol layers only when Ctrl is *not* held.
3. Optionally add Rank 3’s “don’t keyboard_lock on modifiers” even after reorder — holding Ctrl shouldn’t suppress auto-mouse for 500 ms.
4. Avoid Rank 2 unless reorder is blocked by Studio layouts / external docs that hardcode indices.

### Hardware test plan (after a future patch)

| # | Steps | Expect |
|---|--------|--------|
| 1 | RU → hold Ctrl → type letters | Colemak positions + Ctrl, OS stays RU |
| 2 | RU → hold Ctrl → then Lower → arrows/symbols | Lower map, Ctrl still down |
| 3 | RU → hold Lower → then Ctrl | Same as today on Lower’s `&kp LCTRL` |
| 4 | RU → hold Ctrl → roll trackball → LMB | Cursor moves; Mouse buttons work |
| 5 | EN Colemak Ctrl chords | Unchanged (`&kp LCTRL`) |
| 6 | Game / Scroll / Fn | Indices still correct |

---

## 7. Source index

| Claim | Source |
|-------|--------|
| Higher layer index wins; activation order irrelevant | [zmk.dev/docs/keymaps](https://zmk.dev/docs/keymaps) |
| `&trans` / `&none` | [zmk.dev misc behaviors](https://zmk.dev/docs/keymaps/behaviors/misc) |
| Layer+mod macro / `&lm` | [zmk.dev macros](https://zmk.dev/docs/keymaps/behaviors/macros) |
| Nested `&mo` activates but higher opaque layer shadows | [zmk#2382](https://github.com/zmkfirmware/zmk/issues/2382) |
| Conditional layers; then-layer must be higher | [zmk.dev conditional-layers](https://zmk.dev/docs/keymaps/conditional-layers) |
| Local: `&ru_ctrl`, CtrlColemak, Lower/Raise Ctrl | `behavior_ru_ctrl.dtsi`, `charybdis.keymap` |
| Local: auto-mouse lock + Mouse=2 | `auto_mouse_layer.c`, `Kconfig.defconfig` |
| Local: freeze strips mods on Lower/Raise | `lang_switch_freeze.c` |
| Product intent Ctrl-RU | `todo.md`, `todo-priority.md` |

---

## 8. One-line root cause

**`CtrlColemak` is layer 9 above Mouse/Lower/Raise, so `&ru_ctrl`’s `&mo 9` permanently shadows those layers; Raise-then-Ctrl works only because Raise’s own `&kp LCTRL` never raises CtrlColemak. Auto-mouse lock on `LCTRL` is a second, smaller contributor to “mouse dead.”**
