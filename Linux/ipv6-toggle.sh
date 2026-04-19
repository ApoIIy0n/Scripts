#!/usr/bin/env bash
# ipv6-toggle.sh - Disable or re-enable IPv6 and apply/remove IPv4 preference overrides
# Author: Apollyon | https://github.com/ApoIIy0n/Scripts
# Version: 1.0 (2026-04-19)

set -Eeuo pipefail

readonly VERSION="2.2"
readonly SCRIPT_NAME="$(basename "$0")"

readonly SYSCTL_FILE="/etc/sysctl.conf"
readonly APT_FILE="/etc/apt/apt.conf.d/99force-ipv4"
readonly GAI_FILE="/etc/gai.conf"

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
  $SCRIPT_NAME [options] <apply|undo|status>

${BOLD}Options:${RESET}
  -h, --help       Show this help message
  -v, --version    Show version information

${BOLD}Commands:${RESET}
  apply            Disable IPv6 and force/prefer IPv4 where relevant
  undo             Re-enable IPv6 and remove IPv4-only overrides
  status           Show the current IPv6/IPv4 preference status

${BOLD}Examples:${RESET}
  sudo $SCRIPT_NAME apply
  sudo $SCRIPT_NAME undo
  $SCRIPT_NAME status
EOF
}

check_deps() {
  local missing=()
  local cmd

  for cmd in grep sed cp date sysctl rm mkdir touch cat; do
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

backup_file() {
  local file="$1"

  if [[ -f "$file" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    cp -a "$file" "${file}.bak-${ts}"
    info "Backed up $file to ${file}.bak-${ts}"
  fi
}

set_sysctl_key() {
  local key="$1"
  local value="$2"

  touch "$SYSCTL_FILE"

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_FILE"; then
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$SYSCTL_FILE"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$SYSCTL_FILE"
  fi
}

remove_sysctl_key() {
  local key="$1"
  [[ -f "$SYSCTL_FILE" ]] || return 0
  sed -i "\|^[[:space:]]*${key}[[:space:]]*=|d" "$SYSCTL_FILE"
}

set_apt_force_ipv4() {
  mkdir -p /etc/apt/apt.conf.d
  cat > "$APT_FILE" <<'EOF'
Acquire::ForceIPv4 "true";
EOF
}

remove_apt_force_ipv4() {
  rm -f "$APT_FILE"
}

set_gai_prefer_ipv4() {
  touch "$GAI_FILE"

  if grep -Eq '^[[:space:]]*#?[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' "$GAI_FILE"; then
    sed -i 's|^[[:space:]]*#\?[[:space:]]*precedence[[:space:]]\+::ffff:0:0/96[[:space:]]\+100.*|precedence ::ffff:0:0/96  100|' "$GAI_FILE"
  else
    printf '\nprecedence ::ffff:0:0/96  100\n' >> "$GAI_FILE"
  fi
}

remove_gai_prefer_ipv4() {
  [[ -f "$GAI_FILE" ]] || return 0
  sed -i '\|^[[:space:]]*precedence[[:space:]]\+::ffff:0:0/96[[:space:]]\+100|d' "$GAI_FILE"
}

sysctl_key_value() {
  local key="$1"
  sysctl -n "$key" 2>/dev/null || printf 'unknown\n'
}

file_has_sysctl_key() {
  local key="$1"
  [[ -f "$SYSCTL_FILE" ]] && grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_FILE"
}

status_report() {
  local all_runtime default_runtime lo_runtime
  all_runtime="$(sysctl_key_value net.ipv6.conf.all.disable_ipv6)"
  default_runtime="$(sysctl_key_value net.ipv6.conf.default.disable_ipv6)"
  lo_runtime="$(sysctl_key_value net.ipv6.conf.lo.disable_ipv6)"

  printf '  %sRuntime sysctl:%s\n' "$BOLD" "$RESET"
  printf '    net.ipv6.conf.all.disable_ipv6      : %s\n' "$all_runtime"
  printf '    net.ipv6.conf.default.disable_ipv6  : %s\n' "$default_runtime"
  printf '    net.ipv6.conf.lo.disable_ipv6       : %s\n' "$lo_runtime"

  printf '\n  %sPersistent config:%s\n' "$BOLD" "$RESET"
  printf '    %s present: %s\n' "$SYSCTL_FILE" "$([[ -f "$SYSCTL_FILE" ]] && printf 'yes' || printf 'no')"
  printf '    %s present   : %s\n' "$APT_FILE" "$([[ -f "$APT_FILE" ]] && printf 'yes' || printf 'no')"
  printf '    %s present   : %s\n' "$GAI_FILE" "$([[ -f "$GAI_FILE" ]] && printf 'yes' || printf 'no')"

  printf '\n  %sOverrides:%s\n' "$BOLD" "$RESET"
  printf '    sysctl disable keys configured : %s\n' "$(
    if file_has_sysctl_key "net.ipv6.conf.all.disable_ipv6" \
      || file_has_sysctl_key "net.ipv6.conf.default.disable_ipv6" \
      || file_has_sysctl_key "net.ipv6.conf.lo.disable_ipv6"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
  printf '    apt ForceIPv4 enabled          : %s\n' "$(
    if [[ -f "$APT_FILE" ]] && grep -Fq 'Acquire::ForceIPv4 "true";' "$APT_FILE"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
  printf '    gai IPv4 precedence set        : %s\n' "$(
    if [[ -f "$GAI_FILE" ]] && grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' "$GAI_FILE"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
}

apply_changes() {
  info "Backing up config files..."
  backup_file "$SYSCTL_FILE"
  backup_file "$GAI_FILE"
  backup_file "$APT_FILE"

  info "Disabling IPv6 persistently..."
  set_sysctl_key "net.ipv6.conf.all.disable_ipv6" "1"
  set_sysctl_key "net.ipv6.conf.default.disable_ipv6" "1"
  set_sysctl_key "net.ipv6.conf.lo.disable_ipv6" "1"

  info "Applying IPv6 disable immediately..."
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
  sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null

  info "Forcing IPv4 for apt..."
  set_apt_force_ipv4

  info "Preferring IPv4 in address selection..."
  set_gai_prefer_ipv4

  success "IPv6 disabled and IPv4 forced/preferred where relevant."
  warn "A reboot is recommended."

  printf '\n%sChecks after reboot:%s\n' "$BOLD" "$RESET"
  printf '  ping -6 google.com\n'
  printf '  apt update\n'
}

undo_changes() {
  info "Backing up config files..."
  backup_file "$SYSCTL_FILE"
  backup_file "$GAI_FILE"
  backup_file "$APT_FILE"

  info "Re-enabling IPv6 in persistent config..."
  remove_sysctl_key "net.ipv6.conf.all.disable_ipv6"
  remove_sysctl_key "net.ipv6.conf.default.disable_ipv6"
  remove_sysctl_key "net.ipv6.conf.lo.disable_ipv6"

  info "Applying IPv6 re-enable immediately..."
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null

  info "Removing apt IPv4-only setting..."
  remove_apt_force_ipv4

  info "Removing IPv4 preference override..."
  remove_gai_prefer_ipv4

  success "IPv6 re-enabled and IPv4-only overrides removed."
  warn "A reboot is recommended."

  printf '\n%sChecks after reboot:%s\n' "$BOLD" "$RESET"
  printf '  ping -6 google.com\n'
  printf '  apt update\n'
}

main() {
  check_deps

  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -v|--version)
      printf '%s v%s\n' "$SCRIPT_NAME" "$VERSION"
      exit 0
      ;;
    status)
      status_report
      exit 0
      ;;
    apply|undo)
      need_root "$@"
      ;;
    *)
      usage
      exit 1
      ;;
  esac

  case "$1" in
    apply)
      apply_changes
      ;;
    undo)
      undo_changes
      ;;
  esac
}

main "$@"