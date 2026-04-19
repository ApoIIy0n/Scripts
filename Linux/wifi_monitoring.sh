#!/usr/bin/env bash
# wifi_monitoring.sh - Toggle a wireless interface between monitor and managed modes
# Author: Apollyon | https://github.com/ApoIIy0n/Scripts
# Version: 2.0 (2026-04-19)

set -Eeuo pipefail

readonly VERSION="2.2"
readonly SCRIPT_NAME="$(basename "$0")"

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  RESET=''
fi

info()    { printf '%s[*]%s %s\n' "$CYAN" "$RESET" "$*"; }
success() { printf '%s[✓]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()    { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
error()   { printf '%s[✗]%s %s\n' "$RED" "$RESET" "$*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
  cat <<EOF
${BOLD}Usage:${RESET}
  $SCRIPT_NAME [options] <interface> <monitor|managed>

${BOLD}Options:${RESET}
  -h, --help       Show this help message
  -v, --version    Show version information
  -s, --status     Show current mode of an interface and exit

${BOLD}Arguments:${RESET}
  <interface>      Wireless interface name (e.g. wlan0, wlp3s0)
  <mode>           Target mode: monitor | managed
                   Aliases: true → monitor, false → managed

${BOLD}Examples:${RESET}
  $SCRIPT_NAME wlan0 monitor
  $SCRIPT_NAME wlan0 managed
  $SCRIPT_NAME --status wlan0
EOF
}

check_deps() {
  local missing=()
  local cmd

  for cmd in ip iw; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  (( ${#missing[@]} == 0 )) || die "Missing required tools: ${missing[*]}"
}

need_root() {
  if (( EUID != 0 )); then
    command -v sudo >/dev/null 2>&1 || die "Must run as root or have sudo available."
    exec sudo -- "$0" "$@"
  fi
}

iface_exists() {
  iw dev "$1" info >/dev/null 2>&1
}

get_mode() {
  local iface="$1"
  iw dev "$iface" info 2>/dev/null | awk '$1 == "type" { print $2; exit }'
}

iface_state() {
  local iface="$1"
  ip -br link show "$iface" 2>/dev/null | awk '{print $2}'
}

iface_status() {
  local iface="$1"
  iface_exists "$iface" || die "Wireless interface '$iface' not found."

  local mode state
  mode="$(get_mode "$iface")"
  state="$(iface_state "$iface")"

  printf '  Interface : %s%s%s\n' "$BOLD" "$iface" "$RESET"
  printf '  Mode      : %s%s%s\n' "$CYAN" "${mode:-unknown}" "$RESET"
  printf '  State     : %s\n' "${state:-unknown}"
}

normalise_mode() {
  case "${1,,}" in
    true|monitor)  printf 'monitor\n' ;;
    false|managed) printf 'managed\n' ;;
    *)
      die "Unknown mode '$1'. Use: monitor | managed (or true | false)"
      ;;
  esac
}

set_mode() {
  local iface="$1"
  local target="$2"

  iface_exists "$iface" || die "Wireless interface '$iface' not found."

  local current
  current="$(get_mode "$iface")"
  [[ -n "$current" ]] || die "Could not determine current mode for '$iface'."

  if [[ "$current" == "$target" ]]; then
    success "$iface is already in ${BOLD}${target}${RESET} mode."
    return 0
  fi

  info "Changing $iface from ${BOLD}$current${RESET} to ${BOLD}$target${RESET}..."

  info "Bringing $iface down..."
  ip link set dev "$iface" down

  info "Setting $iface to ${BOLD}${target}${RESET} mode..."
  iw dev "$iface" set type "$target"

  info "Bringing $iface up..."
  ip link set dev "$iface" up

  local new_mode
  new_mode="$(get_mode "$iface")"

  if [[ "$new_mode" == "$target" ]]; then
    success "$iface is now in ${BOLD}${target}${RESET} mode."
  else
    die "Mode switch failed — reported mode is '${new_mode:-unknown}'. Driver or hardware may not support '$target'."
  fi
}

main() {
  check_deps
  need_root "$@"

  local status_only=false

  while [[ "${1:-}" == -* ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -v|--version)
        printf '%s v%s\n' "$SCRIPT_NAME" "$VERSION"
        exit 0
        ;;
      -s|--status)
        status_only=true
        shift
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  if $status_only; then
    [[ $# -eq 1 ]] || die "--status requires exactly one interface name."
    iface_status "$1"
    exit 0
  fi

  [[ $# -eq 2 ]] || {
    usage
    exit 1
  }

  local iface="$1"
  local mode
  mode="$(normalise_mode "$2")"

  set_mode "$iface" "$mode"
}

main "$@"