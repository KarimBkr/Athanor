#!/usr/bin/env bash
# =============================================================================
#  Athanor (macOS): administrator rights for the installations, allowed once.
#  Installs the helper system/mac/athanor-admin into /Library/Athanor (owned by root) and a sudo rule
#  that lets your account run it, and only it, without a password: Claude can then install .pkg
#  installers and let the project's programs receive connections, with nobody there to type a password.
#  Asks for your password once (sudo).
#    commands/allow-admin-mac.sh           allow
#    commands/allow-admin-mac.sh --remove  withdraw (removes the helper and the sudo rule)
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1
KIT=$(pwd)
[ "$(uname -s)" = Darwin ] || { echo "This script is for macOS (on Windows: allow-admin.cmd)." >&2; exit 2; }
REGLE=/etc/sudoers.d/athanor
DOSSIER=/Library/Athanor
if [ "${1:-}" = "--remove" ]; then
  sudo rm -f "$REGLE" && sudo rm -rf "$DOSSIER" && echo "Administrator rights withdrawn." || exit 1
  exit 0
fi
compte=$(id -un)
[[ "$compte" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Unexpected account name: $compte" >&2; exit 1; }
echo "Athanor: allowing the installations with administrator rights (your password, once)."
t=$(mktemp) || exit 1
trap 'rm -f "$t"' EXIT
printf '# Athanor: the administrator helper, nothing else, without a password (commands/allow-admin-mac.sh --remove)\n%s ALL=(root) NOPASSWD: %s/athanor-admin\n' "$compte" "$DOSSIER" > "$t"
/usr/sbin/visudo -cf "$t" >/dev/null || { echo "Invalid sudo rule: nothing was changed." >&2; exit 1; }
sudo /bin/bash -c '
  set -e
  install -d -o root -g wheel -m 755 "$1"
  install -o root -g wheel -m 755 "$2" "$1/athanor-admin"
  printf "%s\n%s\n" "$3" "$4" > "$1/racines"; chown root:wheel "$1/racines"; chmod 644 "$1/racines"
  install -o root -g wheel -m 440 "$5" "$6"
' _ "$DOSSIER" "$KIT/system/mac/athanor-admin" "$KIT/tools/mac" "$HOME" "$t" "$REGLE" || { echo "Not allowed (password refused?)." >&2; exit 1; }
mkdir -p "$KIT/tools/mac"
sudo -n -l "$DOSSIER/athanor-admin" >/dev/null 2>&1 && echo "OK: Claude can install .pkg installers and set the firewall without asking. Withdraw with: commands/allow-admin-mac.sh --remove" \
  || { echo "The sudo rule is not active: check /etc/sudoers includes /etc/sudoers.d." >&2; exit 1; }
