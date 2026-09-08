# Blender (Linux): `!` / `@` при Lower/Raise (смена языка)

Дата: 2026-09-07  
Репо: `charybdis-colemak-rus`  
Статус: research only — прошивка не менялась.

---

## Problem statement

На Linux **только в текстовых полях Blender**: при удержании Lower (слой символов + временный переход ОС на EN) раскладка ОС переключается корректно, но иногда в поле ввода появляется `!`, а при отпускании Lower иногда появляется `@`.

Подозрение пользователя: конфликт OS language switch (стиль Alt+Shift / Alt+Shift+N) с обработкой текста в Blender.

Симптом **не** про «чужие» клавиши с Lower-слоя: freeze как раз дропает посторонний ввод. Симптом совпадает с **самими** HID-хорддами смены языка, которые прошивка шлёт на press/release.

---

## Root-cause analysis

### 1. Что реально шлёт эта прошивка

#### Lower / Raise — модуль `lang_switch_freeze` (dongle)

Источник: [`zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c`](../../zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c).

| Событие | Условие | HID-логика в коде |
|--------|---------|-------------------|
| **Press** Lower (pos 37) или Raise (pos 40) | всегда | `release_all_modifiers()` → sleep 5 ms → `tap_lang_combo(LA(LS(N1)))` = **Alt+Shift+1** (OS → EN) |
| **Release** Lower/Raise | активен ZMK-слой Russian (`layer 1`) | то же → `tap_lang_combo(LA(LS(N2)))` = **Alt+Shift+2** (OS → RU) |
| Release на Colemak | слой RU не активен | **ничего** для ОС-языка |

Параллельно `&mo LOWER` / `&mo RAISE` поднимают слой как обычно (`ZMK_EV_EVENT_BUBBLE` на thumb).

Freeze (~50 ms, `CONFIG_ZMK_LANG_SWITCH_FREEZE_MS`) ставит `input_frozen` и на **другие** `position_state_changed` возвращает `ZMK_EV_EVENT_HANDLED` — это режет лишний ввод с матрицы, но **не отменяет** сами `raise_zmk_keycode_state_changed_from_encoded` для Alt+Shift+N.

Документировано в репо: [`todo-priority.md`](../../todo-priority.md) («Отпуск Lower/Raise на RU-слое → Alt+Shift+2»), [`todo.md`](../../todo.md).

#### Esc hold EN/RU — другой путь (макросы)

Источник: [`config/behaviors/behavior_esc_layer_switch.dtsi`](../../config/behaviors/behavior_esc_layer_switch.dtsi).

```dts
bindings = <&macro_press &kp LALT &kp LSHFT>
         , <&macro_tap &kp N1>   /* или N2 для RU */
         , <&macro_release &kp LSHFT &kp LALT>;
```

Порядок: **сначала моды**, потом digit, потом release модов; `wait-ms` / `tap-ms` = 5; перед этим `macro_release_mods` + пауза 30 ms.

#### Keymap thumbs

[`config/charybdis.keymap`](../../config/charybdis.keymap):

- Colemak: `&to_rus LALT 0` · `&mo LOWER` · Space · Ret · `&mo RAISE`
- Russian: `&to_eng LALT 0` · `&mo LOWER` · …

Позиции thumb по умолчанию: Lower=37, Raise=40 ([`Kconfig`](../../zmk_extra_modules/lang_switch_freeze/Kconfig), [`Kconfig.defconfig`](../../boards/shields/charybdis/Kconfig.defconfig)).

Dongle: `CONFIG_ZMK_LANG_SWITCH_FREEZE=y`, `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT=y` ([`charybdis_dongle.conf`](../../boards/shields/charybdis/charybdis_dongle.conf)).

### 2. Почему именно `!` и `@` — HID / раскладка US

USB HID Keyboard/Keypad Page (0x07):

| Usage | Ключ (легенда US) |
|-------|-------------------|
| `0x1E` | **1** / **!** |
| `0x1F` | **2** / **@** |

Первичные таблицы: [USB HID usage tables (Keyboard page)](https://www.freebsddiary.org/APC/usb_hid_usages.php), [Apple IOHIDUsageTables.h](https://github.com/apple-oss-distributions/IOHIDFamily/blob/02b1f53c/IOHIDFamily/IOHIDUsageTables.h) (`kHIDUsage_Keyboard1 = 0x1E /* 1 or ! */`, `…2 = 0x1F /* 2 or @ */`).

Хост **не получает символ `!` от клавиатуры** — получает usage `1` + bit Shift (и часто Alt). Символ строится xkb/IME/приложением.

Совпадение 1:1 с симптомом:

- press Lower → прошивка шлёт **N1** (+ Alt+Shift) → при «утечке» как Shift+1 на US → **`!`**
- release на RU-слое → **N2** (+ Alt+Shift) → утечка как Shift+2 на US → **`@`**

На русской xkb Shift+2 обычно **`"`** (quotedbl), не `@`. Наблюдаемый **`@`** ⇒ символ интерпретируется по **английской** карте (или Blender смотрит «латинский» state) в момент события digit — согласуется с тем, что на press ОС уже ушла в EN, а на release digit обрабатывается до/мимо полного restore RU.

### 3. Чем Lower-путь хуже Esc-макроса

`tap_lang_combo()`:

```c
raise_zmk_keycode_state_changed_from_encoded(encoded, true, t);
raise_zmk_keycode_state_changed_from_encoded(encoded, false, now_ms());
```

- Один encoded `LA(LS(N1))`: моды как **implicit modifiers** вместе с digit (см. [ZMK Modifiers](https://zmk.dev/docs/keymaps/modifiers)).
- **Нет** паузы между press и release.
- `CONFIG_ZMK_LANG_SWITCH_COMBO_MS` (default 35) **объявлен в Kconfig и не используется** в `.c`.

Известные проблемы ZMK с порядком модов у `&kp XX(code)`:

- [#2905](https://github.com/zmkfirmware/zmk/issues/2905) — release модификаторов vs key; mitigation: `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT` (у вас уже `y` на dongle; см. также [ZMK System config — HID](https://zmk.dev/docs/config/system)).
- [#3349](https://github.com/zmkfirmware/zmk/issues/3349) — **иногда** down модификатора приходит **после** down самой клавиши → intermittent wrong character.

Официальные макросы ZMK для последовательностей рекомендуют `wait-ms` / `tap-ms` ≥ ~30 ms, иначе HID-нотификации могут схлопнуться/переупорядочиться ([Macros — Keycode Sequences](https://zmk.dev/docs/keymaps/behaviors/macros)). Esc-путь ближе к этому; Lower — нет.

Итог: даже при «правильном» OS shortcut Alt+Shift+1/2, **гонка порядка Alt/Shift/digit** на Lower делает утечку символа **интермиттирующей** — ровно как описано («sometimes»).

### 4. Почему чаще/заметнее в Blender text fields (Linux)

Blender на Linux не «просто GTK entry»: ввод идёт через GHOST → xkb / `XLookupString` / utf8 в UI text buttons.

- X11: [`GHOST_SystemX11.cc`](https://github.com/blender/blender/blob/1eb4c9cd/intern/ghost/intern/GHOST_SystemX11.cc) — `XLookupString` / `Xutf8LookupString` для ascii/utf8 на key press.
- Wayland: [`GHOST_SystemWayland.cc`](https://github.com/blender/blender/blob/2375ab40/intern/ghost/intern/GHOST_SystemWayland.cc) — xkb state + compose → utf8 для текста.
- Текстовый ввод в keymap матчится как любое press с непустым ascii/utf8 (`TEXTINPUT` / `ISKEYBOARD && (ascii || utf8)` — см. обсуждение в [Blender Stack Exchange: TEXTINPUT](https://blender.stackexchange.com/questions/27535/what-is-event-type-textinput-used-for)).

Типичное поведение X11/`XLookupString`: для генерации печатного символа часто учитываются Shift/Lock, а **Alt (Mod1) не «съедает» символ** так, как accelerator в GTK. Тогда **один и тот же** HID-отчёт Alt+Shift+1 может:

1. сработать как глобальный switch раскладки в DE/IME, **и**
2. дать Blender utf8 **`!`** через lookup Shift+1.

В обычных приложениях shortcut часто **потребляется** shell/WM до виджета; Blender со своим event loop + text buttons — классический кандидат на double-delivery. Дополнительно у Blender долгая история багов с layouts на Linux (например [#47228](https://projects.blender.org/blender/blender/issues/47228), Wayland layout [#115160](https://projects.staging.blender.org/ZedDB/blender/commit/258a0830667502efd8826e97c8e4c56268479967) / [#120892](https://projects.blender.org/blender/blender/issues/120892)) — не root cause `!`/`@`, но объясняет, почему «только Blender».

Конфликты Alt+Shift с приложениями на GNOME — отдельно задокументированы ([Launchpad #1245473](https://bugs.launchpad.net/ubuntu/+source/gnome-shell/+bug/1245473), [GNOME Shell #6373](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/6373)).

### 5. Сводка причинно-следственной цепи

```
Hold Lower on RU layer
  → lang_switch_freeze: Alt+Shift+1 (EN)
  → Blender text: иногда XLookup/xkb → '!'   (HID 1 + Shift, Alt не спасает)
  → &mo LOWER: символьный слой (ок)

Release Lower while ZMK Russian still active
  → Alt+Shift+2 (RU)
  → Blender text: иногда → '@'               (HID 2 + Shift на US-карте)
```

Пользовательское подозрение **верно по направлению**: это OS layout chords. Уточнение: источник символов — **не «магия Blender»**, а **утечка digit-ключей N1/N2** из firmware language combos в text-input path Blender.

---

## Solution options (для этого репо)

Ранжирование: предпочтительнее выше.

### Вариант A — Firmware: выровнять Lower/Raise с Esc-макросом (sequential + COMBO_MS)

**Что:** в `lang_switch_freeze.c` заменить `tap_lang_combo(LA(LS(Nn)))` на явную последовательность как в `macro_os_eng` / `macro_os_rus`:

1. press `LALT`, `LSHFT`
2. `k_msleep(CONFIG_ZMK_LANG_SWITCH_COMBO_MS)` (или split press/tap)
3. tap `N1` / `N2`
4. release `LSHFT`, `LALT` (порядок как в dtsi; с учётом уже включённого `SEPARATE_MOD_RELEASE_REPORT`)

**Файлы:** `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c`; опционально пробросить значение в `charybdis_dongle.conf`.

**Плюсы:** минимальный diff; Kconfig `COMBO_MS` уже есть; тот же OS contract (Alt+Shift+1/2).  
**Минусы:** если Blender всё равно делает char lookup при Alt+Shift+digit, `!`/`@` могут остаться реже, но не исчезнуть на 100%.  
**Оценка:** лучший **первый** фикс.

### Вариант B — Firmware + OS: хоткей без печатных символов (рекомендация «жёстко»)

**Что:** сменить OS binding EN/RU с `Alt+Shift+1/2` на комбинацию, которая **не даёт utf8** в Blender TEXTINPUT, например:

- `Alt+F13` / `Alt+F14`, или
- `Ctrl+Shift+F13` / `F14`, или
- `LA(F13)` / `LA(F14)`  

и зеркально поменять:

- `send_os_english` / `send_os_russian` в `lang_switch_freeze.c`
- `macro_os_eng` / `macro_os_rus` в `behavior_esc_layer_switch.dtsi`

**Плюсы:** бьёт в корень (нет usage 1/2 → нет `!`/`@` по HID-таблице US).  
**Минусы:** нужна синхронная правка DE/IME (GNOME Custom Shortcuts / KDE / `keyd`); F-keys выше F12 требуют NKRO extended на некоторых хостах ([ZMK HID NKRO extended](https://zmk.dev/docs/config/system)).  
**Оценка:** лучший **долгосрочный** фикс для Blender.

### Вариант C — Firmware + OS: numpad `KP_N1` / `KP_N2`

**Что:** `LA(LS(KP_N1))` / `KP_N2` + те же биндинги в ОС.

**Плюсы:** часто не мапятся в `!`/`@` в text fields (зависит от NumLock/xkb).  
**Минусы:** менее предсказуемо на Wayland/разных DE; всё ещё Shift+digit-класс; нужна проверка на железе.  
**Оценка:** дешёвый эксперимент между A и B.

### Вариант D — OS-only: перехват chord до приложения (`keyd` / `kanata` / compositor)

**Что:** оставить прошивку; на Linux демон/комpositor **съедает** Alt+Shift+1/2 и сам переключает layout (`gsettings`, `ibus engine`, `hyprctl`, …), не доставляя digit в focused client.

**Плюсы:** без перепрошивки; точечно для Linux/Blender.  
**Минусы:** вне репо; Esc и Lower должны слать один и тот же chord; поддержка двух машин.  
**Оценка:** ок как workaround, не как единственный путь в firmware roadmap.

### Не рекомендуется как основной фикс

- Только крутить `ZMK_LANG_SWITCH_FREEZE_MS` — freeze **не** блокирует собственные lang keycodes.
- Отключить restore RU на release Lower — уберёт `@`, но сломает UX «печатаю RU → Lower символы на EN → отпустил → снова RU»; `!` на press останется.
- Слепой `grp:alt_shift_toggle` вместо N1/N2 — потеряете **абсолютный** EN/RU (toggle vs to-layout).

---

## Recommended fix

1. **Сразу:** Вариант **A** — sequential Alt/Shift → digit → release + реальный `COMBO_MS` (≥ 30–40 ms), паритет с Esc. Проверить в Blender text field + `evtest`/`wev` на Linux.
2. **Если A не убивает симптом полностью:** Вариант **B** (F13/F14 или аналог без printable) для обоих путей (freeze + esc macros) + OS shortcuts.
3. Параллельно можно быстро проверить **C** одной прошивкой, если не хочется трогать F13.

Критерий успеха: в focused Blender string/search property при press/release Lower на RU-слое **нет** вставки `!`/`@`, при этом ОС EN на hold и RU на release сохраняются.

---

## Implementation notes (куда править)

| Цель | Файл | Что менять |
|------|------|------------|
| Lower/Raise OS chords | `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c` | `send_os_english` / `send_os_russian` / `tap_lang_combo`; использовать `CONFIG_ZMK_LANG_SWITCH_COMBO_MS` |
| Тайминги | `zmk_extra_modules/lang_switch_freeze/Kconfig`, опц. `boards/shields/charybdis/charybdis_dongle.conf` | `ZMK_LANG_SWITCH_COMBO_MS`, при необходимости `FREEZE_MS` |
| Esc hold EN/RU | `config/behaviors/behavior_esc_layer_switch.dtsi` | `macro_os_eng` / `macro_os_rus` — **тот же** chord, что и freeze |
| Keymap thumbs (если UX) | `config/charybdis.keymap` | `&mo LOWER`/`RAISE` позиции; не источник `!`/`@` |
| Сборка | `.\build.ps1` / `verify` | модуль линкуется с dongle через `boards/shields/charybdis/CMakeLists.txt` |

### Поведение «как есть» (для тестов)

```
RU layer + Lower down  => HID: clear mods; Alt+Shift+1 ; layer Lower on
RU layer + Lower up    => HID: clear mods; Alt+Shift+2 ; layer Lower off
EN layer + Lower down  => HID: Alt+Shift+1 ; Lower on
EN layer + Lower up    => (no lang HID)
```

### Диагностика на Linux (без смены прошивки)

1. `wev` / `evtest` на устройстве dongle: при Lower должны мелькать KEY_LEFTALT, KEY_LEFTSHIFT, KEY_1 / KEY_2.
2. Тот же жест вне Blender (gedit/GTK) — если символов нет, а в Blender есть → подтверждение app-side lookup.
3. Временно перебиндить OS switch на Super+Space only и **закомментировать** (локально) `send_os_*` — если `!`/`@` пропадут, вина 100% этих отчётов.

### Связанный долг в репо

- `todo.md`: Lower «плавающие» символы — MVP freeze есть; replay очереди нет; тонкая настройка таймеров — открыта.
- Неиспользуемый `CONFIG_ZMK_LANG_SWITCH_COMBO_MS` — прямой маркер недоделанного sequential combo.

---

## Sources

### Этот репозиторий

- `zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c`
- `zmk_extra_modules/lang_switch_freeze/Kconfig`
- `config/behaviors/behavior_esc_layer_switch.dtsi`
- `config/charybdis.keymap`
- `boards/shields/charybdis/charybdis_dongle.conf`
- `todo.md`, `todo-priority.md`

### ZMK (primary)

- [Modifiers](https://zmk.dev/docs/keymaps/modifiers) — `LA`/`LS` как modifier functions
- [Macros](https://zmk.dev/docs/keymaps/behaviors/macros) — порядок press/tap/release; рекомендация ≥30 ms для последовательностей
- [System config — `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT`](https://zmk.dev/docs/config/system)
- [zmk#2905](https://github.com/zmkfirmware/zmk/issues/2905), [zmk#3349](https://github.com/zmkfirmware/zmk/issues/3349) — порядок модов в HID

### HID / host mapping

- USB HID Keyboard usages `0x1E` = 1/!, `0x1F` = 2/@ — [HID usage table](https://www.freebsddiary.org/APC/usb_hid_usages.php), [IOHIDUsageTables.h](https://github.com/apple-oss-distributions/IOHIDFamily/blob/02b1f53c/IOHIDFamily/IOHIDUsageTables.h)

### Blender / Linux input

- Blender GHOST X11 / Wayland keyboard → utf8 для UI text
- [Blender#47228](https://projects.blender.org/blender/blender/issues/47228) — layout / keysym vs string
- GNOME layout shortcut conflicts: [LP#1245473](https://bugs.launchpad.net/ubuntu/+source/gnome-shell/+bug/1245473), [gnome-shell#6373](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/6373)
