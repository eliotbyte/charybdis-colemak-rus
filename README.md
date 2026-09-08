# Charybdis — Colemak + Russian (dongle)

ZMK user config: split Charybdis 3×6, BLE dongle, Studio, trackball.

## Build (local only)

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```powershell
.\build.ps1              # fast (default): ~3–6 min after first full build
.\build.ps1 right        # one half only (~1–2 min)
.\build.ps1 firmware     # all four UF2 + zip (first run or rare clean rebuild)
```

Outputs (gitignored):

| Path | Contents |
|------|----------|
| `dist/bundle/left.uf2` | Left half |
| `dist/bundle/right.uf2` | Right half |
| `dist/bundle/dongle.uf2` | Dongle (nice!nano v2) |
| `dist/bundle/reset.uf2` | `settings_reset` for nice!nano |
| `dist/charybdis-firmware.zip` | All four files |

| Command | When |
|---------|------|
| `.\build.ps1` / `fast` | Keymap tweaks: incremental + parallel halves + dongle |
| `.\build.ps1 halves` | Only left + right |
| `.\build.ps1 left` / `right` / `dongle` | Single board |
| `.\build.ps1 verify` | Compile dongle only, no `dist/` |
| `.\build.ps1 firmware` | Clean `dist/`, rebuild reset UF2 |
| `.\build.ps1 firmware -Pristine` | Force pristine rebuild all targets |

First run: `.\build.ps1 firmware` (downloads ZMK/Zephyr via `west` into `zmk/`, `zephyr/`, `modules/` — long once). Later `fast` skips `west update` and reuses `build/docker/*` object files.

Refresh west modules after `config/west.yml` changes:

```powershell
.\build.ps1 fast -WestUpdate
```

## Keymap diagram (local)

Manual YAML for [keymap-drawer](https://github.com/caksoylar/keymap-drawer) — not parsed from firmware.

```powershell
pip install keymap-drawer
.\scripts\draw-keymap.ps1
```

- `keymap-drawer/charybdis.yaml` — layers **Colemak**, **Russian** (edit legends here)
- `keymap-drawer/charybdis-new.yaml` — duplicate for visual layout experiments (`draw_config` at bottom)
- `keymap-drawer/config.yaml` — draw/parse options
- output: `keymap-drawer/charybdis.svg` (add `-New` → `charybdis-new.svg`, or `-All` for both)

After changing physical keys in `config/charybdis.keymap`, refresh positions (keep manual labels):

```powershell
keymap parse -c 12 -z config/charybdis.keymap -b keymap-drawer/charybdis.yaml
```

## Layout

- `config/` — keymap, `west.yml`, overlays
- `keymap-drawer/` — layout diagrams (manual)
- `boards/shields/charybdis/` — shield DTS/Kconfig
- `boards-module/` — board root for west
- `zmk_extra_modules/auto_mouse_layer/` — sources (linked from shield)
- `scripts/` — Docker build entrypoints

No GitHub Actions. Planned work (local keymap drawer, sleep policy, …) is listed in **[AGENTS.md](AGENTS.md)** — read it before larger changes.
