# Lang switch: input drop vs key buffer/replay

**Status:** research only (no firmware changes)  
**Date:** 2026-09-07  
**Repo:** `charybdis-colemak-rus`  
**Related:** `todo.md` (Lower / «плавающие» символы), `todo-priority.md` (replay-очередь vs drop-freeze)

---

## 1. Problem

When the user holds **Lower** or **Raise**, firmware forces the OS input language toward English (`Alt+Shift+1`) so symbol layers match US/Colemak HID usages. There is a non-zero window while Windows (or IBus/fcitx/xkb) applies the layout change. Keys pressed in that window are either:

- **Wrong glyphs** — HID usages land under the *old* OS layout, or
- **Dropped** — by design of `lang_switch_freeze` (~50 ms quarantine).

Desired UX (from product notes): queue presses during the switch and **replay** them after the OS has finished switching. Current notes say replay was deferred: freeze+drop is “enough in practice,” but remains an open design fork (`todo-priority.md`: *replay-очередь языка* vs *drop-freeze — разные дизайны*).

Esc-hold EN/RU (`&to_eng` / `&to_rus`) is a related path: same OS hotkeys via macros, **without** the freeze module.

---

## 2. Current implementation (this repo)

### 2.1 Where it lives

| Piece | Path / config |
|-------|----------------|
| Listener module | `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c` |
| Kconfig (module copy) | `zmk_extra_modules/lang_switch_freeze/Kconfig` |
| Kconfig (shield defaults) | `boards/shields/charybdis/Kconfig.defconfig` |
| Compile into dongle | `boards/shields/charybdis/CMakeLists.txt` when `CONFIG_ZMK_LANG_SWITCH_FREEZE` |
| Enable flag | `boards/shields/charybdis/charybdis_dongle.conf` → `CONFIG_ZMK_LANG_SWITCH_FREEZE=y` |
| Esc hold macros | `config/behaviors/behavior_esc_layer_switch.dtsi` |
| Thumb bindings | `config/charybdis.keymap` — `&mo LOWER` / `&mo RAISE` on Colemak + Russian |

Dongle also has `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT=y` so modifier release ordering is safer around OS combos ([ZMK system HID docs](https://zmk.dev/docs/config/system), [app/Kconfig](https://github.com/zmkfirmware/zmk/blob/main/app/Kconfig)).

### 2.2 Defaults

From Kconfig / defconfig:

| Symbol | Default | Role |
|--------|---------|------|
| `ZMK_LANG_SWITCH_LOWER_POS` | `37` | Thumb `&mo LOWER` |
| `ZMK_LANG_SWITCH_RAISE_POS` | `40` | Thumb `&mo RAISE` |
| `ZMK_LANG_SWITCH_RUSSIAN_LAYER` | `1` | ZMK layer index for Russian |
| `ZMK_LANG_SWITCH_FREEZE_MS` | `50` | Quarantine length |
| `ZMK_LANG_SWITCH_COMBO_MS` | `35` | **Declared but unused in `.c`** |

Matrix order in `charybdis.dtsi` (3×12 + 5 thumbs) puts thumbs at positions `36…40`. Keymap order matches: `to_lang`, **LOWER=37**, Space, Ret, **RAISE=40**.

`charybdis_dongle.conf` does **not** override `FREEZE_MS`; runtime is the 50 ms default unless set elsewhere.

### 2.3 Control flow (`lang_switch_freeze.c`)

Listener on `zmk_position_state_changed` only (not `keycode_state_changed`).

```
position event
 ├─ position ∈ {LOWER, RAISE}
 │   ├─ press  → start_freeze_window(); submit lang_to_eng_work
 │   └─ release ∧ Russian layer active → start_freeze_window(); submit lang_to_rus_work
 │   └─ always ZMK_EV_EVENT_BUBBLE  ← &mo still runs
 └─ else ∧ input_frozen → ZMK_EV_EVENT_HANDLED  ← DROP (no keymap invoke)
 └─ else → BUBBLE
```

Work items:

1. `release_all_modifiers()` — synthetic release of L/R Shift/Ctrl/Alt/GUI via `raise_zmk_keycode_state_changed_from_encoded(..., false, ...)`.
2. `k_msleep(5)` — hardcoded (not `COMBO_MS`).
3. Tap OS combo:
   - EN: `LA(LS(N1))` → Alt+Shift+1  
   - RU: `LA(LS(N2))` → Alt+Shift+2  
   as press+release of the encoded combo.

Freeze window:

- `atomic_set(&input_frozen, 1)`
- reschedule delayable work for `FREEZE_MS`
- on expiry: `atomic_clear(&input_frozen)`

**There is no queue.** Handled events are discarded. No `ZMK_EV_EVENT_CAPTURED`, no ring buffer, no re-raise.

### 2.4 Esc-hold path (parallel, no freeze)

`behavior_esc_layer_switch.dtsi`:

1. `macro_release_mods` — release all mods  
2. `macro_wait_time 30`  
3. `macro_os_eng` / `macro_os_rus` — press Alt+Shift, tap N1/N2, release  
4. `&to 0` / `&to 1` — ZMK base layer switch  

Same OS hotkeys; concurrent typing during the macro is **not** quarantined. Upstream ZMK explicitly has an open gap here: macros run on a behavior queue while normal keys still flow ([zmk#2650](https://github.com/zmkfirmware/zmk/issues/2650)).

### 2.5 Why Lower/Raise forces EN

Lower/Raise bindings are normal `&kp` HID usages (punctuation, numbers, etc.). With OS layout = Russian, those same usages produce Cyrillic or wrong symbols. Firmware therefore:

- **On Lower/Raise press:** push OS → EN (and ZMK `&mo` raises the symbol layer).  
- **On release while ZMK Russian layer active:** restore OS → RU.

That dual sync (ZMK layer ↔ OS HKL) is the root of the race: two independent state machines, one HID pipe.

### 2.6 Intentional drop semantics

From `todo.md` / hardware validation: ~50 ms drop avoids “floating” wrong characters. Trade-off is lost keystrokes if the user rolls into Lower symbols (or types) inside that window. Replay was explicitly left out of the MVP.

---

## 3. ZMK / Zephyr patterns (primary sources)

### 3.1 Event quarantine primitives

From [ZMK Events docs](https://github.com/zmkfirmware/zmk/blob/main/docs/docs/development/events.md) / [`event_manager.c`](https://github.com/zmkfirmware/zmk/blob/main/app/src/event_manager.c):

| Return | Effect |
|--------|--------|
| `ZMK_EV_EVENT_BUBBLE` | Continue to later listeners |
| `ZMK_EV_EVENT_HANDLED` | Stop propagation; manager owns lifetime |
| `ZMK_EV_EVENT_CAPTURED` | Stop propagation; listener owns / must release |

Docs warn: **external modules are linked before core ZMK**, so they see `position_state_changed` *before* hold-tap/keymap. Modules should generally **not** handle/capture forever without releasing later. Current freeze returns `HANDLED` (permanent drop) — allowed mechanically, but it is exactly the “disable input” half of [zmk#2650](https://github.com/zmkfirmware/zmk/issues/2650), not the “queue then flush” half.

Events are **stack-allocated** after the events refactor ([zmk#1722](https://github.com/zmkfirmware/zmk/pull/1722)): anything kept across the callback must be **copied** into module storage, then re-raised later via `raise_zmk_position_state_changed` / `ZMK_EVENT_RAISE_AFTER`.

### 3.2 Closest upstream “replay”

[zmk#3384](https://github.com/zmkfirmware/zmk/pull/3384) — USB HID report ring + flush when USB becomes ready (`CONFIG_ZMK_USB_HID_REPLAY_ON_READY`). **Different problem:** transport not-ready, not OS layout latency. Still useful as a pattern: static ring, delayable flush, absolute HID state ordering caveats.

There is **no** in-tree ZMK “input quarantine + position replay for macros/layout.” [zmk#2650](https://github.com/zmkfirmware/zmk/issues/2650) remains open; caksoylar notes the dual queue (behavior/macro vs regular) as the structural cause.

### 3.3 Macros as delayed keys

[Macro behavior docs](https://zmk.dev/docs/keymaps/behaviors/macros): `wait-ms`, `tap-ms`, `&macro_wait_time`, behavior queue size (`CONFIG_ZMK_BEHAVIORS_QUEUE_SIZE`). Macros can delay *their own* sequence; they **cannot** by themselves block or reorder concurrent key events. Esc-hold already uses waits; that does not protect overlapping presses.

### 3.4 QMK analogy (not portable, design only)

QMK tap-hold / deferred processing buffers ambiguous events until resolution ([QMK tap_hold](https://docs.qmk.fm/tap_hold)); community ring-buffer gists exist for custom pending keys. ZMK hold-tap uses event capture/release similarly, but **layout-switch quarantine is custom userspace/module territory** either way.

---

## 4. OS-side options (reduce or remove need for firmware replay)

Firmware cannot observe “OS layout ready.” Anything timed in ZMK is a **heuristic**. Host-side approaches change the race shape:

### 4.1 Windows dedicated per-language hotkeys

Windows Language bar → Advanced Key Settings lets you bind **specific** shortcuts to a given input language (community / MS Q&A: [SuperUser layout hotkeys](https://superuser.com/questions/958901/set-shortcuts-to-change-keyboard-layout-in-windows-10), [MS Learn Q&A on custom sequences](https://learn.microsoft.com/en-us/answers/questions/4354667/how-to-switch-input-language-to-user-defined-key)).

This repo already targets **Alt+Shift+1 / Alt+Shift+2** as fixed EN/RU — correct *if* the OS is configured that way. Latency remains: the host still processes a multi-key HID sequence asynchronously. Sticky mods make it worse; hence mod release + `SEPARATE_MOD_RELEASE_REPORT`.

CapsLock-as-layout: Windows does not expose CapsLock as a first-class layout toggle in the limited Toggle registry set (`Hotkey` values 1–4 only — Alt+Shift / Ctrl+Shift / disabled / grave). Tools like [LangLock](https://github.com/risenxxx/LangLock) intercept CapsLock and send `WM_INPUTLANGCHANGEREQUEST` (same path Win+Space / Alt+Shift use), avoiding a long HID chord from the keyboard. Still async at the app; Raymond Chen documents process-wide layout application and hangs if UI threads do not pump messages ([Old New Thing, 2026-05](https://devblogs.microsoft.com/oldnewthing/20260513-00/?p=112318); API: [`ActivateKeyboardLayout`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-activatekeyboardlayout)).

**Speculation (flagged):** a tiny host daemon could (a) switch layout via `ActivateKeyboardLayout` / `WM_INPUTLANGCHANGEREQUEST` on a HID vendor report or unused key, and (b) optionally hook/queue input until `WM_INPUTLANGCHANGE` — that would be true “ready” signalling, but it is OS software, not ZMK.

### 4.2 Linux: IBus / fcitx5 / xkb

| Stack | Lever | Source |
|-------|-------|--------|
| IBus | `org.freedesktop.ibus.general switcher-delay-time`: `0` = show immediately, **negative = switch without popup** | [ArchWiki IBus](https://wiki.archlinux.org/title/IBus), [ibus.schemas](https://github.com/ibus/ibus/blob/master/data/ibus.schemas.in) |
| IBus | Known delayed switch under load → mixed-language words | [AskUbuntu: iBus on busy system](https://askubuntu.com/questions/550114/ibus-on-busy-system) |
| fcitx5 | `TriggerKeys`, `EnumerateGroupForwardKeys`, CapsLock-capable KeyLists | [fcitx5 `globalconfig.cpp`](https://github.com/fcitx/fcitx5/blob/master/src/lib/fcitx/globalconfig.cpp) |
| XKB | `grp:caps_toggle`, `grp:win_space_toggle`, `grp:alt_shift_toggle` | [ArchWiki Xorg keyboard](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration#Switching_between_keyboard_layouts) |

xkb/group toggles are often **faster and more predictable** than IME popups, but they still do not give firmware an ACK. Negative IBus switcher delay removes UI delay only.

### 4.3 Architectural escape: stop needing OS switch on Lower

If Lower symbols did not depend on OS EN (Unicode macros, OS-specific custom layouts, or “symbols only while already on Colemak base”), momentary Lower would not need `lang_to_eng_work`. That eliminates most of this problem class. Cost: redesign of RU workflow (Esc hold / RU layer already dual-state).

---

## 5. Feasibility: true key-replay queue in ZMK

### 5.1 Sketch

Extend `lang_switch_freeze` on the dongle:

1. On freeze start: same as now (mods clear + OS combo work).  
2. While frozen: for non-thumb positions, **copy** `{position, state, timestamp}` into a fixed ring; return `HANDLED`.  
3. On freeze end (and preferably after lang work finished): clear frozen flag; for each queued item, `raise_zmk_position_state_changed` via **`ZMK_EVENT_RAISE_AFTER(lang_switch_freeze, …)`** so the freeze listener does not immediately re-drop them.  
4. Optional: end freeze on **work completion + settle_ms** instead of a single blind `FREEZE_MS`.

### 5.2 Hard parts

| Issue | Why it hurts |
|-------|----------------|
| No OS ACK | Replay may still land under wrong HKL if settle too short; too long adds lag. |
| Layer context | During Lower hold, replayed positions resolve to **Lower** bindings — usually what you want. If user released Lower before flush, replayed presses hit the wrong layer. |
| Press/release pairing | Press in freeze, release after: today press is dropped, release may bubble → usually HID no-op. With queue: must enqueue both or synthesize matching release. |
| Held keys across boundary | Absolute HID state: replaying press then getting a live release is OK; reverse is bad. |
| Combos / hold-taps | Replayed positions re-enter hold-tap/combo logic with fresh timestamps — may mis-detect taps. |
| Esc path | Separate macros; replay module would need sharing or Esc stays unprotected. |
| Listener priority | Module-first is good for intercept; flush must skip self (`RAISE_AFTER`). |
| Docs guidance | Permanent `HANDLED` without release is discouraged; queue+flush is the “correct” module pattern. |
| BLE split | Central (dongle) already sees positions — good place for the queue; peripherals need no change. |

### 5.3 Effort estimate

| Approach | Effort | Risk |
|----------|--------|------|
| Tune `FREEZE_MS` / end freeze after work | small | low |
| Event-driven quarantine (no replay) | small–medium | low |
| Position ring + replay | medium | medium (edge cases) |
| Host daemon with ACK | medium–large | process/install dependency |
| Remove OS switch from Lower | large (UX redesign) | high product impact |

**Verdict:** A true ZMK replay queue is **feasible on the dongle** as an evolution of `lang_switch_freeze`, but it does **not** guarantee correctness without an OS settle heuristic. Upstream will not solve this soon ([#2650](https://github.com/zmkfirmware/zmk/issues/2650) open). USB HID replay ([#3384](https://github.com/zmkfirmware/zmk/pull/3384)) is unrelated.

---

## 6. Proposed solutions

### A — Best practical (recommended default): keep drop-freeze, make it precise

1. Measure worst-case EN/RU switch latency on the user’s Windows box (keyboard tester / log).  
2. Set `CONFIG_ZMK_LANG_SWITCH_FREEZE_MS` in `charybdis_dongle.conf` to that + small margin (may be >50).  
3. End freeze from **lang work completion + settle**, not only from press+50 ms (today freeze starts before the 5 ms sleep + combo; race against workqueue).  
4. Delete or wire `COMBO_MS` (currently dead).  
5. Accept rare dropped keys inside the window — matches validated MVP.

**Pros:** matches `todo-priority` “на практике хватает”; tiny change.  
**Cons:** still drops, not replays.

### B — Soft quarantine without full replay

- Quarantine only until OS combo HID reports are sent (+ settle).  
- Or drop only **presses** (allow releases through) to avoid stuck keys.  
- Optionally skip quarantine when already OS-EN (needs host feedback — generally unavailable).

**Pros:** fewer false drops than fixed 50 ms.  
**Cons:** still no replay.

### C — OS / workflow changes (avoid firmware replay)

- Confirm Windows per-language hotkeys match Alt+Shift+1/2.  
- Prefer Win+Space or CapsLock→`WM_INPUTLANGCHANGEREQUEST` helper for *manual* switches; keep firmware chords for automatic Lower sync.  
- On Linux: xkb `grp:…` or IBus `switcher-delay-time=-1`.  
- Long-term: dedicated lang key (`todo.md` backlog) that does not coincide with symbol-layer rolls.

**Pros:** less firmware complexity.  
**Cons:** does not fully remove Lower-hold race while dual sync remains.

### D — Ideal replay queue (only if A/B still fail on hardware)

Implement §5.1 in `lang_switch_freeze.c`:

- Ring depth ~8–16 position events (press+release pairs).  
- Flush after `max(work_done, FREEZE_MS)` with `RAISE_AFTER`.  
- Explicit tests: roll into Lower symbols; release Lower before flush; Esc-hold overlap; sticky mods.

**Pros:** closest to requested UX.  
**Cons:** non-trivial edge cases; still timer-based; conflicts with “don’t mix replay and drop-freeze designs” unless freeze becomes “queue mode” behind a Kconfig.

---

## 7. Recommendation

1. **Ship/keep A** as the production strategy unless hardware still shows wrong glyphs after tuning.  
2. Treat **D** as optional Kconfig (`ZMK_LANG_SWITCH_REPLAY=y`) only after measuring that users actually press keys inside the quarantine more often than they tolerate drops.  
3. Do **not** expect upstream ZMK macros or USB HID replay to solve this.  
4. Parallel product lever: dedicated language key / less OS switching on momentary layers (C + backlog item in `todo.md`).

---

## 8. Sources

### This repo

- `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c`
- `zmk_extra_modules/lang_switch_freeze/Kconfig`
- `boards/shields/charybdis/{CMakeLists.txt,Kconfig.defconfig,charybdis_dongle.conf,charybdis.dtsi}`
- `config/behaviors/behavior_esc_layer_switch.dtsi`
- `config/charybdis.keymap`
- `todo.md`, `todo-priority.md`

### ZMK / Zephyr

- [ZMK Events (development docs)](https://github.com/zmkfirmware/zmk/blob/main/docs/docs/development/events.md)
- [event_manager.c](https://github.com/zmkfirmware/zmk/blob/main/app/src/event_manager.c)
- [Macros](https://zmk.dev/docs/keymaps/behaviors/macros)
- [HID / `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT`](https://zmk.dev/docs/config/system)
- [zmk#2650 — queue/disable inputs while macro running](https://github.com/zmkfirmware/zmk/issues/2650)
- [zmk#3384 — USB HID report queue/replay](https://github.com/zmkfirmware/zmk/pull/3384)
- [zmk#1722 — stack-allocated events](https://github.com/zmkfirmware/zmk/pull/1722)

### OS / IME

- [ActivateKeyboardLayout (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-activatekeyboardlayout)
- [Old New Thing — WM_INPUTLANGCHANGEREQUEST hangs](https://devblogs.microsoft.com/oldnewthing/20260513-00/?p=112318)
- [Windows language hotkeys (SuperUser)](https://superuser.com/questions/958901/set-shortcuts-to-change-keyboard-layout-in-windows-10)
- [MS Q&A — limited custom language hotkeys](https://learn.microsoft.com/en-us/answers/questions/4354667/how-to-switch-input-language-to-user-defined-key)
- [LangLock — CapsLock → WM_INPUTLANGCHANGEREQUEST](https://github.com/risenxxx/LangLock)
- [ArchWiki — IBus switcher-delay-time](https://wiki.archlinux.org/title/Ibus)
- [ArchWiki — XKB layout switching / grp:caps_toggle](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration#Switching_between_keyboard_layouts)
- [fcitx5 HotkeyConfig](https://github.com/fcitx/fcitx5/blob/master/src/lib/fcitx/globalconfig.cpp)
- [AskUbuntu — IBus busy-system switch delay](https://askubuntu.com/questions/550114/ibus-on-busy-system)

### Speculative (not verified in this pass)

- Host-side input hook that queues keystrokes until `WM_INPUTLANGCHANGE` / equivalent on Linux — would beat any firmware timer; out of ZMK scope.
