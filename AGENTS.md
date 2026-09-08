# Agent guide — charybdis-colemak-rus

Документ для людей и для агентов: что уже есть, что **намеренно не делаем**, и **что ещё предстоит**.

---

## Цели проекта

- Прошивка Charybdis 3×6: **Colemak + Russian**, dongle (central), ZMK Studio, трекбол, auto-mouse layer.
- **Только локальная разработка:** Docker на Windows, без GitHub Actions и без GitHub Releases.
- Репозиторий **чистый:** в git только исходники конфига; артефакты сборки и west-кэш — снаружи git.

Источник логики keymap/поведений: перенос из `zmk-corne-wireless-colemak` + политика сна/питания из prospector-dongle репо (не копировать чужие `*.conf` про сон слепо).

---

## Roadmap

### Сделано (не ломать без причины)

| # | Что | Где |
|---|-----|-----|
| 1 | Чистый репо: config, boards, boards-module, auto_mouse sources | корень |
| 2 | Локальная сборка в Docker (`zmk-build-arm:stable`) | `docker-compose.yml`, `scripts/`, `build.ps1` |
| 3 | Дефолтный вывод прошивки: **left, right, dongle, reset** (nice!nano v2) | `dist/bundle/*.uf2`, `dist/charybdis-firmware.zip` |
| 4 | Быстрая сборка UF2 | `.\build.ps1` (`fast`, default) или `.\build.ps1 right` |
| 4b | Проверка компиляции без UF2 | `.\build.ps1 verify` |
| 5 | `.gitignore`: `zmk/`, `zephyr/`, `modules/`, `build/`, `dist/` | не коммитить артефакты |
| 6 | `boards-module` в git (`/zephyr/` в ignore — только корень репо) | `boards-module/zephyr/module.yml` |
| 7 | auto_mouse без дубля в `ZMK_EXTRA_MODULES` | `boards/shields/charybdis/CMakeLists.txt` |
| 8 | Dongle: `CONFIG_ZMK_SLEEP=n` | `charybdis_dongle.conf` |

### Запланировано (ещё не в репо — это следующие задачи)

#### A. Keymap drawer (локально, **без** CI)

**Зачем:** SVG/YAML схема раскладки для себя; парсер [keymap-drawer](https://github.com/caksoylar/keymap-drawer) плохо понимает кастомные behaviors (`&to_eng`, `&to_rus`, `&hold`, pointing).

**Требования:**

- Только **локальный** запуск (`pip install keymap-drawer` или отдельный маленький Docker-сервис — на усмотрение реализации).
- **Не** добавлять `.github/workflows` для отрисовки.
- **Не** коммитить сгенерированные SVG в каждый push (опционально: коммитить вручную или держать в `docs/` — решить при реализации).
- Картинка может **не совпадать 1:1** с прошивкой: источник правды для рисунка — `keymap-drawer/charybdis.yaml` (ручной YAML), а не слепой parse из `.keymap`.
- Подписи behaviors: `parse_config.raw_binding_map` в `keymap-drawer/config.yaml` (`&to_eng` → `EN`, `&to_rus` → `RU`, `&hold`, `&studio_unlock` → `Studio`, и т.д.).
- Цвета/стили: `draw_config.svg_extra_style`, per-key `type: held | trans | ghost` в YAML ([KEYMAP_SPEC](https://github.com/caksoylar/keymap-drawer/blob/main/KEYMAP_SPEC.md)).
- Workflow для человека (добавить в README при реализации):
  ```powershell
  keymap -c keymap-drawer/config.yaml draw keymap-drawer/charybdis.yaml > keymap-drawer/charybdis.svg
  ```
  При смене физических клавиш в keymap — `keymap parse -z config/charybdis.keymap -b keymap-drawer/charybdis.yaml` чтобы обновить структуру, сохранив ручные подписи.

**Критерий готовности:** одна команда (скрипт `scripts/draw-keymap.ps1` или аналог) рисует SVG; документировано в README; CI нет.

#### B. Политика сна / трекбол (прошивка)

**Контекст:** deep sleep **только правой** половины (или асимметрия с донглом) давал баги: мёртвый трекбол, reset донгла/правой. Power cycle лечит.

**Запланировано (если понадобится экономия батареи):**

- Явно задокументировать и при необходимости добавить в `config/charybdis_right.conf`:
  - `CONFIG_ZMK_SLEEP=n` на правой (и согласованная политика на left/dongle), **или**
  - синхронный `CONFIG_ZMK_SLEEP=y` + один `CONFIG_ZMK_IDLE_SLEEP_TIMEOUT` на **все** части split.
- Опционально: `CONFIG_PMW3610_ALT_INIT_POWER_UP_EXTRA_DELAY_MS` после экспериментов.
- **Не** включать sleep на донгле при awake peripheral без теста.

**Критерий готовности:** решение записано в README + conf; пользователь подтвердил на железе.

#### C. Удобства сборки (по желанию)

- `scripts/draw-keymap.ps1` / `scripts/build-all.ps1` — тонкие обёртки.
- `SKIP_PRISTINE=1` уже поддержан в `docker-build.sh` — описать в README (есть).
- Отдельный target **только** left+right+dongle без reset — если reset не нужен в zip (сейчас reset в bundle по запросу пользователя).

### Явно вне scope (не предлагать без запроса)

| Не делаем | Почему |
|-----------|--------|
| GitHub Actions (build, drawer, release) | Решение владельца: только локально |
| GitHub Releases / теги с UF2 | Артефакты в `dist/` |
| Сборка xiao / prospector dongle в дефолте | Нужен только nice!nano v2; добавлять отдельным target по запросу |
| Копирование prospector `*.conf` / sleep overlay из старых репо | Своя политика сна |
| Дубль `auto_mouse_layer` в `ZMK_EXTRA_MODULES` | linker error |
| Коммит `zmk/`, `zephyr/`, `build/`, `dist/`, `*.log` | мусор и гигабайты |

---

## Текущее состояние (техническое)

### Сборка

| Команда | Эффект |
|---------|--------|
| `.\build.ps1` | `fast`: incremental parallel halves + dongle → `dist/bundle/` |
| `.\build.ps1 right` / `left` / `dongle` | один UF2 |
| `.\build.ps1 firmware` | полный clean bundle + reset |
| `.\build.ps1 verify` | compile dongle only, no `dist/` |

Образ: `zmkfirmware/zmk-build-arm:stable`.

### Targets (default)

1. `charybdis_left` — `nice_nano/nrf52840/zmk`
2. `charybdis_right` — + PMW3610 (`west.yml` → badjeff `zmk-pmw3610-driver`)
3. `charybdis_dongle` — + `studio-rpc-usb-uart`, `CONFIG_ZMK_STUDIO=y`
4. `settings_reset` — сброс bonding nice!nano

### CMake (все Charybdis shields)

```
-DZMK_EXTRA_MODULES=/work/boards-module
```

### Ключевые файлы keymap

| Файл | Назначение |
|------|------------|
| `config/charybdis.keymap` | слои, combos |
| `config/behaviors/behavior_esc_layer_switch.dtsi` | EN/RU, hold |
| `config/charybdis_dongle.overlay` | pointing на донгле |
| `boards/shields/charybdis/split_input_common.dtsi` | auto_mouse, scroll |

После правок keymap: `.\build.ps1` (fast) или `.\build.ps1 right`; полный `.\build.ps1 firmware` — редко.

---

## Do not commit

- `zmk/`, `zephyr/`, `modules/`, `.west/`, `bootloader/`, `tools/`
- `build/`, `dist/`
- `*.log`, `docker-*.log`
- Случайные west-клоны в корне: `prospector-zmk-module/`, `zmk-pmw3610-driver/` (подтягиваются через `west update`)

---

## Для агента: порядок работы

1. Прочитать **Roadmap** — не реализовывать «Future» без явного запроса пользователя.
2. Правки прошивки → `.\build.ps1 verify` минимум; перед «готово» — `.\build.ps1` если трогали split/dongle/right.
3. Новые файлы в `dist/` / west trees — never `git add`.
4. Drawer (когда дойдёт очередь): только локальный скрипт + `keymap-drawer/`, без `.github/workflows`.
5. Sleep/trackball: сначала документ + conf, потом прошивка; не ломать текущий стабильный `ZMK_SLEEP=n` на донгле.

---

## Связь со старым репо

`charybdis-3-6-dongle-prospector-studio` — прототип с CI, keymap-drawer в Actions, полной `build.yaml` матрицей. **Этот репо — production-local:** урезанный scope, тот же keymap/boards после переноса.

При переносе фич из старого репо: брать только нужное для прошивки; CI/draw workflows **не** переносить.
