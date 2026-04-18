#!/usr/bin/env bash

set -euo pipefail

CORE_SCRIPT="$HOME/fedora-iso-builds/iso-builder.sh"
BUILDS_DIR="$HOME/fedora-iso-builds/builds"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    zenity --error --text="Missing required command: $cmd"
    exit 1
  fi
}

require_cmd zenity
require_cmd bash
require_cmd qemu-system-x86_64

if [[ ! -f "$CORE_SCRIPT" ]]; then
  zenity --error --text="Core script not found:\n$CORE_SCRIPT"
  exit 1
fi

run_core_with_input() {
  local input_data="$1"
  printf "%s" "$input_data" | bash "$CORE_SCRIPT"
}

list_iso_files() {
  find "$BUILDS_DIR" -mindepth 2 -maxdepth 2 -type f \( -name "*.iso" -o -name "fedora_*" -o -name "fedora-*" \) | sort
}

select_iso_gui() {
  mapfile -t ISO_LIST < <(list_iso_files)

  if [[ "${#ISO_LIST[@]}" -eq 0 ]]; then
    zenity --error --text="No ISO builds found."
    return 1
  fi

  local zenity_args=()
  for iso in "${ISO_LIST[@]}"; do
    zenity_args+=("$iso")
  done

  SELECTED_ISO=$(zenity --list \
    --title="Select ISO" \
    --text="Choose an ISO build to test" \
    --column="ISO Path" \
    "${zenity_args[@]}" \
    --height=420 --width=900)

  [[ -n "${SELECTED_ISO:-}" ]]
}

show_builds_gui() {
  mapfile -t ISO_LIST < <(list_iso_files)

  if [[ "${#ISO_LIST[@]}" -eq 0 ]]; then
    zenity --error --text="No ISO builds found."
    return 1
  fi

  local text=""
  for iso in "${ISO_LIST[@]}"; do
    text+="$iso"$'\n'
  done

  zenity --text-info \
    --title="Available ISO Builds" \
    --width=900 \
    --height=500 \
    --filename=<(printf "%s" "$text")
}

run_test_iso_gui() {
  if ! select_iso_gui; then
    return 1
  fi

  ram=$(zenity --entry \
    --title="RAM" \
    --text="Enter RAM in MB" \
    --entry-text="4096")

  [[ -z "${ram:-}" ]] && return 0

  cpus=$(zenity --entry \
    --title="vCPUs" \
    --text="Enter number of vCPUs" \
    --entry-text="4")

  [[ -z "${cpus:-}" ]] && return 0

  zenity --info --text="Starting QEMU with:\n$SELECTED_ISO"

  qemu-system-x86_64 \
    -enable-kvm \
    -m "$ram" \
    -cpu host \
    -smp "$cpus" \
    -cdrom "$SELECTED_ISO"
}

while true; do
  choice=$(zenity --list \
    --title="FedDev ISO Builder v2" \
    --text="Select mode" \
    --column="Option" \
    "Setup" \
    "Build" \
    "Test ISO" \
    "List Builds" \
    "Clean" \
    "Exit" \
    --height=360 --width=360)

  [[ -z "${choice:-}" ]] && exit 0

  case "$choice" in
    "Setup")
      zenity --info --text="Running Setup in terminal..."
      run_core_with_input $'1\n'
      ;;

    "Build")
      zenity --info --text="Build mode is still using the terminal-driven core flow.\nUse the main builder terminal for the full interactive build."
      bash "$CORE_SCRIPT"
      ;;

    "Test ISO")
      run_test_iso_gui
      ;;

    "List Builds")
      show_builds_gui
      ;;

    "Clean")
      if zenity --question --text="Run cleanup mode?"; then
        run_core_with_input $'5\n'
      fi
      ;;

    "Exit")
      exit 0
      ;;
  esac
done
