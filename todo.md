# Charybdis — что допилить



Отмечаем по ходу: `[x]` сделано, `[ ]` ещё нет, `[~]` сделано частично (работает, но не весь план).



---



## Раскладка и язык



- [x] **Ctrl на русском ≠ Colemak**  

  `&ru_ctrl` (`behavior_ru_ctrl.dtsi`): на RU-слое Ctrl поднимает слой `CtrlColemak` (9) + LCTRL; ОС язык не трогаем. Проверено на железе.



- [~] **Lower и «плавающие» символы**  

  **Сделано (MVP, на железе ок):** модуль `lang_switch_freeze` на dongle — зажал Lower или Raise → ~50 ms режем лишний ввод, сбрасываем моды, шлём Alt+Shift+1 (EN); отпустил на русском ZMK-слое → Alt+Shift+2 (RU). Слой `&mo` поднимается как раньше.  

  **Не сделано:** очередь с replay нажатий (пока drop, не «доиграть потом»). Тонкая подстройка таймеров в `charybdis_dongle.conf` (`ZMK_LANG_SWITCH_FREEZE_MS` и т.д.), если где-то ещё дёргается.



- [ ] **Кнопка смены языка**  

  Возможно перенести на другую клавишу или сделать смену через layer вместо текущего варианта — пока просто в бэклоге, без решения.



- [x] **Смена языка и зажатые модификаторы**  

  Esc hold EN/RU: `macro_release_mods` → пауза → Alt+Shift+N1/N2 → `&to`. Lower/Raise — тот же сброс модов в `lang_switch_freeze`. Включён `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT` на dongle.



---



## Игровой режим



- [x] **Слой Game с Fn**  

  Fn (12, последний слой — выше Game): `none` + Norm/Game справа сверху. Game (10), GameLower (11). Выход: Esc hold → Fn → Norm. Scroll=5… `&to 0` (RU не восстанавливается).



---



## Мышь и трекбол



### Auto-mouse (`zmk_extra_modules/auto_mouse_layer/`)



Сейчас на dongle: трекбол поднимает слой Mouse, таймер гасит по idle. На буквенных слоях (Colemak/RU) крутение трекбола Mouse **не** включается (`keyboard_lock`).



- [ ] **Продлевать Mouse от кликов и под-слоёв**  

  - **Ок, не ломать:** печать на Colemak/RU + трекбол без Mouse (lock).  

  - **Ок:** движение трекбола при активном Mouse — таймер **продлевается**.  

  - **Баг:** LMB/RMB (`&mkp`) таймер **не** продлевают — слой падает, пока курсор стоит.  

  - **Баг/UX:** на Scroll (`&mo SCROLL`) / Screen теряется «база» Mouse — клики и скролл без привычного контекста.  

  **Хочется:** клики (и удержание?) LMB/RMB продлевают таймер как трекбол; вход в Scroll/Screen снова держит или поднимает Mouse. Слушатель сейчас только `zmk_keycode_state_changed` — кнопки мыши, похоже, мимо.



- [ ] **Буква на левой половине → сразу выйти из Mouse**  

  Сценарий: повёл мышь, Mouse ещё активен, начинаешь печатать — слой должен **мгновенно** сброситься на Colemak/RU (тот, что был до Mouse), а не ждать таймаут.  

  **Срабатывает:** буквы/цифры/символы на **левой** половине (позиции keymap), связанные с печатью, не с мышью.  

  **Не сбрасывает Mouse (или только продлевает таймер):** Ctrl, Shift, Alt, Tab, Esc и прочие «служебные» — чтобы модификаторы и навигация не роняли Mouse зря.  

  Сейчас при `mouse_active` любое нажатие в `keycode_listener_cb` только **продлевает** таймер — отсюда залипание Mouse при наборе текста. Код: `auto_mouse_layer.c` + при необходимости фильтр по `zmk_keymap_active_layer_index` / позиции клавиши.



- [ ] **Scroll: скорость от скорости трекбола** *(исследование)*  

  Медленное движение — мелкий скролл, быстрое — крупнее. Отдельно от axis snap.



### Трекбол / pointing (dongle overlay)



- [x] **Убрать кнопку и слой замедления курсора**  

  MouseShift и `slow_pointer` убраны; вместо них `zmk-pointing-acceleration` на dongle (`min/max-factor`, без `track-remainders` — меньше «скольжения»). Подкрутка на железе: `config/charybdis_dongle.overlay`.



- [x] **Ускорение курсора от скорости трекбола**  

  `zmk-pointing-acceleration` в overlay (`min/max-factor`, без `track-remainders`). Проверено на железе: ощущения ок.



- [x] **Scroll: зафиксировать ось**  

  `zmk-scroll-snap`, `zip_cursor_snap_8way` в overlay. Проверено на железе (Scroll-слой): ось держится, в целом ок.



- [ ] **Screen + трекбол вместо «зажал и жми стрелки»**  

  На слое мыши кнопка → слой Screen (виртуальные столы). Хочется: зажал, повёл трекбол — **один** хоткей на жест; пауза — следующий рывок снова один раз. Не спамить, пока шарик крутится без остановки.



---



## Заметки



- Код языка: `zmk_extra_modules/lang_switch_freeze/`, `behavior_esc_layer_switch.dtsi`, Kconfig в `boards/shields/charybdis/`.

- Трекбол: `config/charybdis_dongle.overlay`, west: `zmk-pointing-acceleration`, `zmk-scroll-snap` (submodules).

- Auto-mouse: C-модуль на dongle; в `split_input_common.dtsi` ещё `input-processor-temp-layer`, на dongle `auto_mouse_layer` в overlay удалён — логика в C.

- Dongle: при клоне/сборке нужен `west update` для новых модулей.

- Keymap-drawer: MouseShift / MSh в YAML ещё могут быть — не источник правды для прошивки.



*Последнее обновление списка: 2026-06-04*


