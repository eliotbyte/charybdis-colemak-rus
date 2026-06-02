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
  fi
  log "west update (first run is slow; cached under zmk/ zephyr/ modules/)"
  west update --fetch-opt=--filter=tree:0
  west zephyr-export
}

extra_modules() {
  echo "/work/boards-module"
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
  local pristine_flag=(--pristine)

  if [[ "${SKIP_PRISTINE:-}" == "1" ]] && [[ -d "${out_dir}" ]]; then
    pristine_flag=()
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

build_firmware() {
  COPY_UF2=1
  rm -rf dist/bundle dist/*.uf2 dist/*.zip 2>/dev/null || true
  mkdir -p dist/bundle

  build_target charybdis_left-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_left
  cp dist/charybdis_left-nice_nano_v2.uf2 dist/bundle/left.uf2

  build_target charybdis_right-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_right
  cp dist/charybdis_right-nice_nano_v2.uf2 dist/bundle/right.uf2

  build_target charybdis_dongle-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_dongle studio-rpc-usb-uart \
    -DCONFIG_ZMK_STUDIO=y
  cp dist/charybdis_dongle-nice_nano_v2.uf2 dist/bundle/dongle.uf2

  build_target settings_reset-nice_nano_v2 \
    nice_nano/nrf52840/zmk settings_reset
  cp dist/settings_reset-nice_nano_v2.uf2 dist/bundle/reset.uf2

  (cd dist/bundle && zip -j ../charybdis-firmware.zip ./*.uf2)
  log "Bundle: dist/charybdis-firmware.zip (left, right, dongle, reset)"
  ls -la dist/bundle/ dist/charybdis-firmware.zip
}

build_verify() {
  build_target charybdis_dongle-nice_nano_v2 \
    nice_nano/nrf52840/zmk charybdis_dongle studio-rpc-usb-uart \
    -DCONFIG_ZMK_STUDIO=y
}

MODE=${1:-firmware}
COPY_UF2=0

ensure_west

case "$MODE" in
  firmware)
    build_firmware
    ;;
  verify)
    build_verify
    ;;
  *)
    echo "Usage: $0 [firmware|verify]"
    exit 1
    ;;
esac

log "Done."
