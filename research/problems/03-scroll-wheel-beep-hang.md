# 03 — Scroll wheel: system beep + hangy/stuck feel

**Status:** research only (no firmware change)  
**Symptom:** Intermittent PC speaker / system beep while scrolling; scroll sometimes feels stuck, hangy, or continues oddly. Affects mouse/trackball scroll (wheel up/down).  
**Scope:** Charybdis Colemak+RU, dongle central + PMW3610 on right, local ZMK west tree.

---

## Executive verdict

Highest-probability **firmware** cause: `CONFIG_ZMK_POINTING_SMOOTH_SCROLLING=y` on the dongle plus a **confirmed bug in upstream ZMK** `apply_resolution_scaling()` that emits the *unscaled* accumulated wheel value while updating remainder as if scaling happened. That matches “continue/repeat unexpectedly” reports on pointing splits; A/B by disabling smooth scrolling is the cheapest confirmation.

The **beep** is almost certainly **host OS feedback** (GTK error bell / Windows MessageBeep / sticky-Ctrl zoom fail), not a firmware buzzer — this repo has no wheel→haptic/output listener. Over-large or runaway HID wheel deltas (from the smooth-scroll bug, oversized `&msc` values, or hi-res multiplier desync) make apps hit scroll bounds / invalid targets and *then* beep.

---

## 1. What this repo actually sends

### 1.1 Pipeline (dongle = HID to host)

| Stage | Where | What |
|-------|--------|------|
| Sensor | `boards/shields/charybdis/charybdis_3610.dtsi` | PMW3610-alt, CPI 600, `force-awake` + `force-awake-4ms-mode` (~250 Hz), emits `INPUT_REL_X/Y` |
| Right conf | `config/charybdis_right.conf` | `SWAP_XY` + invert X/Y; pointing + PMW3610 |
| Split | `split_input_common.dtsi` → `zmk,input-split` | Right → dongle |
| Listener | dongle enables `&trackball_listener` | `boards/.../charybdis_dongle.overlay` |
| Cursor path | `config/charybdis_dongle.overlay` | base `input-processors = <&pointer_accel>` (`zmk-pointing-acceleration`) |
| Scroll path | same overlay, layer 5 | deletes stock `scroll`; `scroller` on layer 5: snap → map XY→wheel → scale → Y invert |
| HID | ZMK mouse report | buttons + int16 X/Y + int16 wheel + int16 hwheel (AC Pan) |
| Smooth scroll | `charybdis_dongle.conf` | `CONFIG_ZMK_POINTING_SMOOTH_SCROLLING=y` → resolution-multiplier feature report in descriptor |

**Scroll-layer processor chain (authoritative for trackball scroll):**

```dts
/* config/charybdis_dongle.overlay — scroller @ layer 5 */
&zip_cursor_snap_8way
&zip_xy_to_scroll_mapper          /* Y→WHEEL, X→HWHEEL */
&zip_scroll_scaler 30 48          /* ≈ 0.625×, with remainders */
&zip_scroll_transform (INPUT_TRANSFORM_Y_INVERT)
```

Base `pointer_accel` does **not** apply on layer 5 unless `process-next` is set (default false) — layer override returns before the base chain ([ZMK input listener](https://zmk.dev/docs/config/pointing)).

**Key-emulated scroll (separate path):** `config/charybdis.keymap` Scroll / ScrollShift layers use `&msc MOVE_Y/X(...)` with:

```c
SCROLL_BASE = ZMK_POINTING_DEFAULT_SCRL_VAL * 16  /* default SCRL_VAL=10 → 160 */
SCROLL_FAST = SCROLL_BASE * 3                     /* → 480 */
```

Defaults from ZMK [`pointing.h`](https://github.com/zmkfirmware/zmk/blob/main/app/include/dt-bindings/zmk/pointing.h): `ZMK_POINTING_DEFAULT_SCRL_VAL` = 10, move = 600. Docs say that with smooth scrolling you should prefer large `MOVE_*`-scale values for `&msc`, not tiny `SCRL_*` — this keymap already uses inflated values (160/480), which is intentional for hi-res but brutal if the host is still in legacy tick mode.

### 1.2 Shared `split_input_common.dtsi` scroll (overridden on dongle)

```dts
scroll {
  layers = <SCROLL>;
  input-processors =
    <&zip_xy_transform (INPUT_TRANSFORM_Y_INVERT)>,
    <&zip_xy_scaler 1 3>,
    <&zip_xy_to_scroll_mapper>;
};
```

Dongle **deletes** this node and replaces it with snap + `zip_scroll_scaler 30 48`. Comment in overlay: *“split_input_common scroll@layer5 wins first — no snap; must delete”*. Correct for this build; don’t reintroduce the old child without deleting it again.

### 1.3 HID usages (not “wrong consumer keys”)

Mouse report (local `zmk/app/include/zmk/hid.h`):

- Wheel → `HID_USAGE_GD_WHEEL` (relative, int16)
- Horizontal → Consumer **AC Pan** (standard h-scroll), int16
- With smooth scrolling: feature report Resolution Multiplier (4+4 bits), logical 0..15, physical 1..16

Scroll layers bind `&msc` / `&mkp` only — **no** `C_VOL_*` / media on Scroll. Lower layer has volume keys; accidental layer bleed is possible but not the primary scroll path. Mis-sent media as the beep source is **low** confidence unless HID capture shows consumer reports during scroll.

### 1.4 Snap / accel notes

- **`zmk-scroll-snap` `zip_cursor_snap_8way`:** snaps on `REL_X/Y` *before* mapper (right approach for trackball). README marks **8-way / diagonal snap incomplete**. This config uses aggressive PMW-tuned thresholds (`require-n-samples=3`, `immediate-snap-threshold=120`, `lock-for-next-n-events=16`, `lock-duration-ms=200`). Axis lock can feel like “stuck” direction for ~200 ms / 16 events — **orthogonal** to beep, but can amplify “hangy” subjective feel.
- **`zmk-pointing-acceleration`:** on cursor path only here; README warns primary testing was Cirque trackpads. Not on scroll chain.

### 1.5 Local west ZMK revision

Checked tree: `zmk` @ `26246da` (main-ish). Smooth-scroll BLE fix [#2998](https://github.com/zmkfirmware/zmk/pull/2998) is present. Scaling emit fix [#3383](https://github.com/zmkfirmware/zmk/pull/3383) is **not** — local code still has the bug (below).

---

## 2. Why scroll causes a system beep (OS side)

Firmware does not drive a PC speaker. Beep = host.

| Mechanism | Platform | How it shows up |
|-----------|----------|-----------------|
| **GTK error / event bell** | Linux (and GTK apps on Windows) | Invalid input / navigation: scroll when widget can’t scroll, already at end, focus on non-scrollable control. Controlled by `gtk-error-bell` / `gtk-enable-event-sounds` ([GTK4 docs](https://docs.gtk.org/gtk4/property.Settings.gtk-error-bell.html); [zim issue #2033](https://github.com/zim-desktop-wiki/zim-desktop-wiki/issues/2033) — beep on Ctrl+End / scroll-at-end). |
| **Sticky / stuck Ctrl + wheel** | Windows (also browsers) | Ctrl+wheel = zoom. Stuck Ctrl (Sticky Keys, BLE mod desync, half disconnect) → zoom instead of scroll; failed/odd zoom often accompanied by system ding. ([MakeUseOf / Sticky Keys](https://www.makeuseof.com/windows-mouse-zoom-instead-of-scroll/); [SuperUser sticky Ctrl](https://superuser.com/questions/775703/google-chrome-opens-new-tab-on-each-link-mousewheel-is-zoom)). |
| **Accessibility Toggle/Sticky Keys feedback** | Windows | Beeps on modifier/lock actions — usually not scroll-specific unless scroll coincides with mod state changes ([PALCS sticky keys](https://support.palcs.org/hc/en-us/articles/13789559640339-Keyboard-issues-Why-is-my-computer-beeping-at-me-keyboard-not-working-right)). |
| **USB EMI / jack buzz** | Rare hardware | Analog crosstalk when *moving* USB mouse — different class of “beep”, not app bell ([SuperUser USB mouse headphone beep](https://superuser.com/questions/602602/beep-in-headphone-when-usb-mouse-is-plugged-in-or-moved)). Unlikely if discrete MessageBeep / GTK bell. |
| **HID flood → overscroll / focus thrash** | Both | Huge or very frequent wheel deltas push UI past end or onto non-scrollable focus → triggers error bell. Links firmware magnitude bugs to OS audio. |

**Not found in this repo:** `zmk,output-behavior-listener` / `OUTPUT_SOURCE_MOUSE_WHEEL_STATE_CHANGE` (that pattern is for intentional haptic “notch” feedback in other configs — [badjeff output-behavior-listener](https://github.com/badjeff/zmk-output-behavior-listener)).

---

## 3. Firmware vs OS — discrimination

### 3.1 Strong firmware suspects

#### A. Smooth-scroll scaling bug (smoking gun for hang/continue)

Local `zmk/app/src/pointing/input_listener.c`:

```c
int16_t val = evt->value + *remainder;
int16_t scaled = val / (int16_t)div;
*remainder = val - (scaled * (int16_t)div);
evt->value = val;   /* BUG: should be scaled */
```

`div = 16 - resolution_multiplier.wheel` (default profile wheel/hor_wheel = **15** → `div = 1` at boot — bug inert until host SET_REPORTs a lower multiplier).

Open PR [#3383](https://github.com/zmkfirmware/zmk/pull/3383) (*fix(pointing): emit scaled smooth scrolling values*, 2026-06): same one-line fix; author reproduced on **split pointing** — with smooth scrolling enabled, trackball scroll **continued/repeated unexpectedly**; disabling smooth scrolling avoided it. Matches this symptom class.

**Interaction with this config:** dongle has `CONFIG_ZMK_POINTING_SMOOTH_SCROLLING=y`. When host negotiates legacy (wheel≈0 → div≈16), device emits full `val` but tracks remainder as if divided → oversized ticks + polluted remainder → hangy / runaway scroll → OS overscroll beep.

#### B. Resolution-multiplier host/device desync after USB reset / sleep

Linux historically: after suspend/reset, device clears feature-report multipliers but host still assumes hi-res → **extremely slow** scroll (opposite of flood). Kernel fix: renegotiate on reset_resume ([commit `d6f4941`](https://github.com/torvalds/linux/commit/d6f4941f1b4f3e701e422dfbfee024264294f91f), UHK issues cited therein). ZMK side: BLE feature-report bugs fixed in [#2998](https://github.com/zmkfirmware/zmk/pull/2998) / issue [#2957](https://github.com/zmkfirmware/zmk/issues/2957) (jumpy scroll over BLE; USB was OK). Dongle is typically **USB** to PC — BLE path less relevant unless also using BLE HID.

Intermittent after sleep/replug → suspect multiplier desync (speed wrong); intermittent while actively spinning → more like #3383 / flood / snap lock.

#### C. Large `&msc` deltas + smooth scrolling

`SCROLL_BASE=160`, `SCROLL_FAST=480` per two-axis tick while held. With hi-res OK; with legacy or buggy scaling, each report is many “notches” → jump + boundary beep. ZMK mouse-emulation docs: with smooth scrolling, prefer move-scale values ([Mouse Emulation](https://zmk.dev/docs/keymaps/behaviors/mouse-emulation)).

#### D. Trackball rate + scaler

PMW3610 `force-awake-4ms-mode` → high event rate. Mapper turns XY into wheel every sync; scaler 30/48 with remainders still passes substantial deltas on fast spin. Can flood HID without being “wrong usage.”

#### E. Snap lock “hang”

`lock-duration-ms=200` + `lock-for-next-n-events=16` zeroes the non-locked axis. Feels sticky; should **not** beep alone unless combined with overscroll from magnitude bugs.

### 3.2 Strong OS / user-state suspects

- Focus on non-scrollable widget / already at document end (GTK bell).
- Stuck Ctrl (Sticky Keys / OSK blue Ctrl / split mod state) → zoom path.
- App-specific scroll handling (browser PDF, terminal, etc.).

### 3.3 Quick triage matrix

| Observation | Points to |
|-------------|-----------|
| Beep only at top/bottom of content | OS error bell; firmware may still overshoot |
| Beep + zoom / font size change | Stuck Ctrl (OS or firmware mod state) |
| Scroll keeps going after finger stops | Smooth-scroll remainder bug (#3383) or host queue |
| Only after sleep/USB re-enum | Multiplier desync |
| Only with trackball, not `&msc` keys | Sensor/snap/scaler path |
| Only with `&msc`, not trackball | SCROLL_BASE magnitude / two-axis accel |
| Gone after `CONFIG_ZMK_POINTING_SMOOTH_SCROLLING=n` | Smooth scroll path (firmware) |
| Gone after `gtk-error-bell=0` / mute system sounds but scroll still wild | OS beep only; firmware magnitude still wrong |
| `libinput debug-events` / USBPcap shows sane ±1..±8 wheel | Firmware OK → OS focus |
| Capture shows ±100..±1000 or continuous stream | Firmware magnitude / flood |

---

## 4. Are HID usages / values “wrong”?

| Check | Result |
|-------|--------|
| Wheel usage | Correct GD Wheel |
| H-scroll | Correct Consumer AC Pan (not a bogus key) |
| Report sizes | int16 — not int8 wrap for moderate values |
| Consumer volume during scroll | Not on Scroll layer bindings |
| Extreme values possible? | **Yes** — bug A + SCRL 160/480 + 250 Hz ball |
| Smooth scroll descriptor | Present only when Kconfig on — changes HID; needs host re-pair/refresh after toggle ([ZMK pointing refresh note](https://zmk.dev/docs/keymaps/behaviors/mouse-emulation)) |

No evidence of accidental media-key HID as the primary beep mechanism.

---

## 5. Ranked fixes (2–4)

### Fix 1 — Highest priority: disable or fix smooth scrolling (firmware)

**Do first (A/B, ~1 flash):**

```ini
# boards/shields/charybdis/charybdis_dongle.conf
# CONFIG_ZMK_POINTING_SMOOTH_SCROLLING=y
CONFIG_ZMK_POINTING_SMOOTH_SCROLLING=n
```

Re-flash **dongle**; refresh HID / re-pair if host caches descriptor. Retest beep + hang.

**Proper fix:** carry [#3383](https://github.com/zmkfirmware/zmk/pull/3383) (`evt->value = scaled`) into the west-pinned ZMK, **or** wait for merge and bump revision. Keep smooth scrolling only after that.

**Why ranked #1:** Direct match to hang/continue; enabled in this repo; bug present in local tree; author reproduction on split pointing.

### Fix 2 — Cap scroll magnitudes (firmware, low risk)

If hang/beep remains with smooth scroll off, or only on key scroll:

- Reduce `SCROLL_BASE` / `SCROLL_FAST` (e.g. toward `SCRL_*` or `*4` instead of `*16` when smooth off).
- Soften trackball: e.g. `&zip_scroll_scaler 15 48` or `20 48`; consider dropping `force-awake-4ms-mode` if flood confirmed.
- Optionally shorten snap locks (`lock-for-next-n-events`, `lock-duration-ms`) if “stuck axis” is the hang feel.

**Why #2:** Addresses extreme HID values without waiting on upstream; easy to tune on hardware.

### Fix 3 — OS triage / sticky modifiers (host + optional firmware hygiene)

- Linux: confirm with `libinput debug-events`; try `gtk-error-bell=0` — if beep dies but motion still wrong, firmware still dirty.
- Windows: OSK → check Ctrl highlighted; disable Sticky Keys shortcut; test whether wheel zooms.
- Firmware: if mods stick across Mouse/Scroll, audit split keycode path / `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT` (already `y` on dongle) and left-half Ctrl while scrolling.

**Why #3:** Explains beep-without-bad-HID and Ctrl+wheel class; needed to stop chasing firmware if OS-only.

### Fix 4 — Multiplier / sleep edge cases (if intermittent after suspend)

- Replug dongle or toggle USB after sleep; note if scroll speed jumps by ~16×.
- Track Linux kernel / host with resolution-multiplier renegotiation; avoid assuming ZMK can fully work around host bugs ([UHK / kernel discussion](https://github.com/torvalds/linux/commit/d6f4941f1b4f3e701e422dfbfee024264294f91f)).
- Don’t treat “sleep → weird scroll” as the same bug as “mid-spin hang” until A/B’d.

**Why #4:** Real class of bugs, but classic symptom is **slow** scroll after resume, not always beep/hang mid-session.

---

## 6. Suggested experiment order (hardware)

1. Flash dongle with smooth scrolling **off** → 10 min Scroll-layer trackball + `&msc`.  
2. If fixed → patch/backport #3383 or stay off; done.  
3. If not fixed → USBPcap / Wireshark USB or Linux `libinput debug-events` during beep; note wheel magnitudes and whether keyboard mods are down.  
4. Mute GTK error bell / check Ctrl sticky → classify beep vs motion.  
5. Tune scaler / `SCROLL_BASE` only after path (trackball vs keys) is known.

---

## 7. Sources

### In-repo

- `config/charybdis_dongle.overlay` — accel, snap, scroller chain  
- `boards/shields/charybdis/split_input_common.dtsi` — default scroll processors  
- `boards/shields/charybdis/charybdis_dongle.conf` — `SMOOTH_SCROLLING`  
- `config/charybdis.keymap` — `&msc` SCROLL_BASE/FAST  
- `boards/shields/charybdis/charybdis_3610.dtsi` — PMW3610  
- Local `zmk/app/src/pointing/input_listener.c` — `apply_resolution_scaling`  
- Local `zmk/app/src/pointing/resolution_multipliers.c` — default wheel=15  
- `zmk-scroll-snap` README + `zip_cursor_snap_8way` incomplete note  
- `zmk-pointing-acceleration` README  

### Upstream / docs

- [ZMK pointing config — smooth scrolling](https://zmk.dev/docs/config/pointing)  
- [ZMK mouse emulation — scroll + smooth note](https://zmk.dev/docs/keymaps/behaviors/mouse-emulation)  
- [ZMK PR #3383 — emit scaled smooth scrolling](https://github.com/zmkfirmware/zmk/pull/3383)  
- [ZMK #2957 / PR #2998 — smooth scroll over BLE](https://github.com/zmkfirmware/zmk/issues/2957)  
- [kot149/zmk-scroll-snap](https://github.com/kot149/zmk-scroll-snap)  
- [QMK hi-res scroll / resolution multiplier semantics](https://github.com/qmk/qmk_firmware/issues/17585)  
- [Linux hid reset_resume renegotiate multipliers](https://github.com/torvalds/linux/commit/d6f4941f1b4f3e701e422dfbfee024264294f91f)  
- [GTK gtk-error-bell](https://docs.gtk.org/gtk4/property.Settings.gtk-error-bell.html)  
- [zim #2033 — beep at scroll/end](https://github.com/zim-desktop-wiki/zim-desktop-wiki/issues/2033)  
- Sticky Ctrl + wheel zoom: [MakeUseOf](https://www.makeuseof.com/windows-mouse-zoom-instead-of-scroll/), [SuperUser](https://superuser.com/questions/775703/google-chrome-opens-new-tab-on-each-link-mousewheel-is-zoom)  

---

## 8. Out of scope / not claimed

- No firmware patch applied in this research pass.  
- Did not capture live HID on your host.  
- Did not bisect whether beep is GTK vs Windows vs stuck Ctrl on your machine — triage steps above.  
- Sleep/trackball power policy (`CONFIG_ZMK_SLEEP`) is a separate roadmap item; only linked here via USB reset ↔ multiplier desync.
