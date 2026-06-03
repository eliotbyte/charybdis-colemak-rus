#!/usr/bin/env bash
# Local ZMK builds in zmkfirmware/zmk-build-arm. Outputs go to dist/ (gitignored).
sed -i 's/\r$//' "$0" 2>/dev/null || true

WORK=/work
cd "$WORK"
mkdir -p dist build/docker

log() { echo "[docker-build] $*"; }

ensure_west() {
  if [[ ! -f .west/config ]]; then
    log "west init -l config"
    west init -l config
    SKIP_WEST_UPDATE=0
  fi
  if [[ "${SKIP_WEST_UPDATE:-1}" == "1" ]] && [[ -f zmk/app/Kconfig ]]; then
    log "west update skipped (set SKIP_WEST_UPDATE=0 to refresh modules)"
    return
  fi
  log "west update (slow; cached under zmk/ zephyr/ modules/)"
  west update --fetch-opt=--filter=tree:0
  west zephyr-export
}

extra_modules() {
  echo "/work/boards-module"
}

should_skip_pristine() {
  local out_dir=$1
  [[ "${PRISTINE:-}" == "1" ]] && return 1
  [[ "${SKIP_PRISTINE:-}" == "1" ]] && [[ -d "${out_dir}" ]] && return 0
  [[ "${INCREMENTAL:-}" == "1" ]] && [[ -d "${out_dir}" ]] && return 0
  return 1
}

build_target() {
  local name=$1 board=$2 shield=$3
  shift 3
  local snippet="" out_dir="build/docker/${name}"
  local -a west_args=()
  local -a cmake_args=(
    -DZMK_CONFIG=/work/config
    -DSHIELD="${shield}"
    "-DZMK_EXTRA_MODULES=$(extra_modules)"
  )
  local -a pristine_flag=(--pristine)

  if should_skip_pristine "${out_dir}"; then
    pristine_flag=()
    log "incremental: ${name}"
  fi

  if (($#)) && [[ "$1" != -* ]]; then
    snippet=$1
    shift
  fi

  if [[ -n "$snippet" ]]; then
    west_args+=(-S "$snippet")
  fi

  if (($#)); then
    cmake_args+=("$@")
  fi

  log "=== build: ${name} (board=${board}, shield=${shield}) ==="
  west build "${pristine_flag[@]}" -s zmk/app -d "$out_dir" -b "$board" "${west_args[@]}" -- "${cmake_args[@]}"

  if [[ ! -f "${out_dir}/zephyr/zmk.uf2" ]]; then
    log "ERROR: build failed (no zmk.uf2)"
    exit 1
  fi

  log "BUILD OK: ${name}"
  if [[ "${COPY_UF2:-}" == "1" ]]; then
    cp "${out_dir}/zephyr/zmk.uf2" "dist/${name}.uf2"
    log "  -> dist/${name}.uf2"
  fi
}

copy_bundle() {
  local name=$1 bundle=$2
  cp "dist/${name}.uf2" "dist/bundle/${bundle}.uf2"
  log "  -> dist/bundle/${bundle}.uf2"
}

build_left() {
  build_target charybdis_left-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_left
}

build_right() {
  build_target charybdis_right-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_right
}

build_dongle() {
  build_target charybdis_dongle-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_dongle studio-rpc-usb-uart \
    -DCONFIG_ZMK_STUDIO=y
}

build_reset() {
  build_target settings_reset-nice_nano_v2 \
    nice_nano/nrf52840/zmk settings_reset
}

build_halves_parallel() {
  local pid_l pid_r st_l st_r
  ( build_left ) &
  pid_l=$!
  ( build_right ) &
  pid_r=$!
  st_l=0
  st_r=0
  wait "${pid_l}" || st_l=$?
  wait "${pid_r}" || st_r=$?
  if [[ "${st_l}" -ne 0 || "${st_r}" -ne 0 ]]; then
    log "ERROR: half build failed (left=${st_l} right=${st_r})"
    exit 1
  fi
}

bundle_zip() {
  mkdir -p dist/bundle
  if command -v zip >/dev/null 2>&1; then
    (cd dist/bundle && zip -j ../charybdis-firmware.zip ./*.uf2)
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import zipfile
from pathlib import Path
bundle = Path("dist/bundle")
out = Path("dist/charybdis-firmware.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for uf2 in sorted(bundle.glob("*.uf2")):
        zf.write(uf2, uf2.name)
print(out)
PY
  else
    log "zip/python3 missing — UF2 in dist/bundle/ only"
    return
  fi
  log "Bundle: dist/charybdis-firmware.zip"
}

prepare_dist() {
  mkdir -p dist/bundle
}

# Incremental keymap iteration: both halves + dongle, no settings_reset.
build_fast() {
  COPY_UF2=1
  INCREMENTAL=1
  prepare_dist
  build_halves_parallel
  copy_bundle charybdis_left-nice_nano_v2 left
  copy_bundle charybdis_right-nice_nano_v2 right
  build_dongle
  copy_bundle charybdis_dongle-nice_nano_v2 dongle
  if [[ -f dist/bundle/reset.uf2 ]]; then
    log "reset.uf2 unchanged (use firmware + PRISTINE=1 to rebuild)"
  elif [[ -f dist/settings_reset-nice_nano_v2.uf2 ]]; then
    cp dist/settings_reset-nice_nano_v2.uf2 dist/bundle/reset.uf2
  fi
  bundle_zip
  ls -la dist/bundle/ 2>/dev/null || true
}

build_halves() {
  COPY_UF2=1
  INCREMENTAL=1
  prepare_dist
  build_halves_parallel
  copy_bundle charybdis_left-nice_nano_v2 left
  copy_bundle charybdis_right-nice_nano_v2 right
}

build_single() {
  local which=$1
  COPY_UF2=1
  INCREMENTAL=1
  prepare_dist
  case "$which" in
    left)
      build_left
      copy_bundle charybdis_left-nice_nano_v2 left
      ;;
    right)
      build_right
      copy_bundle charybdis_right-nice_nano_v2 right
      ;;
    dongle)
      build_dongle
      copy_bundle charybdis_dongle-nice_nano_v2 dongle
      ;;
    *)
      echo "unknown target: $which"
      exit 1
      ;;
  esac
}

build_firmware() {
  COPY_UF2=1
  rm -rf dist/bundle dist/*.uf2 dist/*.zip 2>/dev/null || true
  prepare_dist

  if [[ "${PARALLEL_HALVES:-}" == "1" ]]; then
    build_halves_parallel
  else
    build_left
    build_right
  fi
  copy_bundle charybdis_left-nice_nano_v2 left
  copy_bundle charybdis_right-nice_nano_v2 right

  build_dongle
  copy_bundle charybdis_dongle-nice_nano_v2 dongle

  build_reset
  copy_bundle settings_reset-nice_nano_v2 reset

  bundle_zip
  ls -la dist/bundle/ dist/charybdis-firmware.zip 2>/dev/null || ls -la dist/bundle/
}

build_verify() {
  INCREMENTAL=1
  build_dongle
}

MODE=${1:-fast}
COPY_UF2=0

ensure_west

case "$MODE" in
  firmware)
    build_firmware
    ;;
  fast)
    build_fast
    ;;
  halves)
    build_halves
    ;;
  left|right|dongle)
    build_single "$MODE"
    ;;
  verify)
    build_verify
    ;;
  *)
    echo "Usage: $0 [fast|halves|left|right|dongle|firmware|verify]"
    echo "  fast     — incremental halves (parallel) + dongle → dist/bundle (default)"
    echo "  halves   — incremental left + right only"
    echo "  left|right|dongle — one target"
    echo "  firmware — clean dist + all four UF2 (set PRISTINE=1 for full rebuild)"
    echo "  verify   — compile dongle only, no dist/"
    exit 1
    ;;
esac

log "Done."
