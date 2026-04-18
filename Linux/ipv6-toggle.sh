#!/usr/bin/env bash
set -euo pipefail

SYSCTL_FILE="/etc/sysctl.conf"
APT_FILE="/etc/apt/apt.conf.d/99force-ipv4"
GAI_FILE="/etc/gai.conf"

usage() {
  cat <<'EOF'
Usage:
  sudo bash ipv6-toggle.sh apply   # Disable IPv6 and force IPv4
  sudo bash ipv6-toggle.sh undo    # Re-enable IPv6 and remove IPv4-only overrides
EOF
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root, for example: sudo bash $0 apply"
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    cp -a "$file" "${file}.bak-${ts}"
  fi
}

set_sysctl_key() {
  local key="$1"
  local value="$2"

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

apply_changes() {
  echo "Backing up config files..."
  backup_file "$SYSCTL_FILE"
  backup_file "$GAI_FILE"
  backup_file "$APT_FILE"

  echo "Disabling IPv6 permanently..."
  set_sysctl_key "net.ipv6.conf.all.disable_ipv6" "1"
  set_sysctl_key "net.ipv6.conf.default.disable_ipv6" "1"
  set_sysctl_key "net.ipv6.conf.lo.disable_ipv6" "1"

  echo "Applying IPv6 disable immediately..."
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
  sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null

  echo "Forcing IPv4 for apt..."
  set_apt_force_ipv4

  echo "Preferring IPv4 in address selection..."
  set_gai_prefer_ipv4

  echo
  echo "Done."
  echo "IPv6 disabled and IPv4 forced where relevant."
  echo "A reboot is recommended."
  echo
  echo "Checks after reboot:"
  echo "  ping -6 google.com"
  echo "  apt update"
}

undo_changes() {
  echo "Backing up config files..."
  backup_file "$SYSCTL_FILE"
  backup_file "$GAI_FILE"
  backup_file "$APT_FILE"

  echo "Re-enabling IPv6 in sysctl config..."
  remove_sysctl_key "net.ipv6.conf.all.disable_ipv6"
  remove_sysctl_key "net.ipv6.conf.default.disable_ipv6"
  remove_sysctl_key "net.ipv6.conf.lo.disable_ipv6"

  echo "Applying IPv6 re-enable immediately..."
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null

  echo "Removing apt IPv4-only setting..."
  remove_apt_force_ipv4

  echo "Removing IPv4 preference override..."
  remove_gai_prefer_ipv4

  echo
  echo "Done."
  echo "IPv6 re-enabled and IPv4-only overrides removed."
  echo "A reboot is recommended."
  echo
  echo "Checks after reboot:"
  echo "  ping -6 google.com"
  echo "  apt update"
}

main() {
  require_root

  if [[ $# -ne 1 ]]; then
    usage
  fi

  case "$1" in
    apply)
      apply_changes
      ;;
    undo)
      undo_changes
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"