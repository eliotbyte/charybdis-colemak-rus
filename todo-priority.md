# Порядок работ по Charybdis

Список задач — в [todo.md](todo.md). Здесь очередь и что уже сошлось с прошивкой.

Обновлено: 2026-09-07 (lang freeze gate/quarantine, CtrlColemak=2, smooth scroll off).

---

## Уже в прошивке

| Что | Где |
|-----|-----|
| Lower/Raise → OS EN **только с RU-слоя**; с Colemak без chord/freeze | `lang_switch_freeze` |
| Sequential Alt+Shift → digit → release (`COMBO_MS`); Ctrl не сбрасывается | там же |
| Paired quarantine (drop press+release; уже-held release не глотается) | там же |
| Отпуск Lower/Raise на RU → Alt+Shift+2 | там же |
| Esc hold EN/RU без залипших модов | `behavior_esc_layer_switch.dtsi` |
| Порядок release модов по USB | `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT` |
| Ускорение курсора от скорости трекбола, проверено | `zmk-pointing-acceleration`, `charybdis_dongle.overlay` |
| Scroll axis snap (трекбол → одна ось), проверено на Scroll-слое | `zmk-scroll-snap`, `zip_cursor_snap_8way` |
| Smooth scrolling **выкл** на dongle (hangy wheel / host beep A/B) | `charybdis_dongle.conf` |
| Убраны MouseShift / slow_pointer / кнопка замедления | `charybdis.keymap`, overlay, `split_input_common.dtsi` |
| Слои: CtrlColemak=2, Mouse=3… Scroll=6… Fn=12 | `charybdis.keymap` |
| Ctrl на RU → Colemak-позиции; слой **под** Mouse/Lower/Raise | `&ru_ctrl` `&mo 2`, `behavior_ru_ctrl.dtsi` |
| Mods не ставят `keyboard_lock` (Ctrl + трекбол → Mouse) | `auto_mouse_layer.c` |

Replay-очередь для языка — всё ещё нет; drop + quarantine. F13/F14 хоткеи — не трогали (нужен OS).

Трекбол: accel и snap на Scroll проверены на железе, ок (до выкл. smooth — перепроверить скролл).

Ресёрч: `research/problems/01`…`06`.

---

## Дальше по приоритету

### 1. Auto-mouse (один модуль, два UX)

**A. Продлевать Mouse** — LMB/RMB и под-слои Scroll/Screen продлевают или поднимают Mouse; сейчас клики таймер не сбрасывают. `auto_mouse_layer.c`: подписки на mouse keys / `mkp`, не только `keycode_state_changed`.

**B. Печать рвёт Mouse** — буква (и печатные символы) на **левой** половине при активном Mouse → **сразу** `layer_deactivate(MOUSE)` и возврат к Colemak/RU; Tab/Esc/Ctrl/Shift/Alt — не роняют Mouse. Сейчас любое нажатие при `mouse_active` только продлевает таймер → залипание Mouse при наборе после мыши.

**Не сломать:** Colemak/RU + трекбол без подъёма Mouse (`keyboard_lock`); mods уже исключены из lock.

### 2. Если Lower ещё капризничает

- Тюнить `ZMK_LANG_SWITCH_FREEZE_MS` / `COMBO_MS` в `charybdis_dongle.conf`.
- Опционально replay вместо drop (`research/problems/04`).
- Если `!`/`@` в Blender останутся — F13/F14 + OS (`research/problems/01`).

### 3. Трекбол / мышь (после auto-mouse)

- **Screen + трекбол** — жесты виртуальных столов.
- **Scroll: скорость от скорости** — исследование.
- Если без smooth всё ещё криво — смотреть scaler / sticky Ctrl на хосте (`research/problems/03`).

### 4. Хвост

Перенос кнопки смены языка, keymap-drawer. Game+Fn — в прошивке.

---

## Что не параллелить

| Можно рядом | Не смешивать |
|-------------|--------------|
| auto-mouse A (клики) и B (буква→сброс) | один PR в `auto_mouse_layer.c`, но разные ветки логики — тестировать оба сценария |
| — | lang freeze + CtrlColemak уже связаны; не ломать gate/quarantine вслепую |
| replay-очередь языка | drop-freeze — разные дизайны |

---

## Сводка одной строкой

~~заморозка~~ ~~accel/snap/MouseShift~~ ~~Ctrl-RU overlay~~ ~~Game+Fn~~ ~~lang gate/quarantine/CtrlColemak=2/smooth off~~ → **1:** auto-mouse (клики + буква слева сбрасывает Mouse) → **2:** Screen+трекбол, scroll speed → **3:** lang key / replay / F13.
