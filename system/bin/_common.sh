# shellcheck shell=bash
# Shared functions of the gateways (sourced, not executed).
SYSTEME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$(dirname "$SYSTEME")"
PROJECT="${PROJECT:-$KIT/projet}"
# Native Windows mode (Git Bash): the shims (wslpath…), Windows options passed as they are ("/c", "/T": the
# gateways convert their paths themselves), and the project in Git Bash form (pwd and realpath say /c/...,
# Claude's environment says C:/...)
NATIF=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*)
  NATIF=1
  # no sandbox, so no bridge: the gateways always run directly (for Claude, and for the pilot itself)
  export PATH="$SYSTEME/natif:$PATH" MSYS2_ARG_CONV_EXCL='*' PONT_DIRECT=1
  PROJECT=$(cygpath -u "$PROJECT")
  [ -n "${TOOLS:-}" ] && TOOLS=$(cygpath -u "$TOOLS")
  ;;
esac
# macOS: the GNU tools of Homebrew (stat -c, date +%N…) when the caller did not put them in the PATH
MAC=0
if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
  MAC=1
  for _b in /opt/homebrew /usr/local; do
    [ -d "$_b/opt/coreutils/libexec/gnubin" ] || continue
    case ":$PATH:" in *":$_b/opt/coreutils/libexec/gnubin:"*) ;; *) export PATH="$_b/opt/coreutils/libexec/gnubin:$_b/bin:$PATH" ;; esac
    break
  done
  unset _b
fi
[ -f "$SYSTEME/pc_tools.env" ] && . "$SYSTEME/pc_tools.env"

# Converts Linux paths to Windows paths for a .exe program (also "-opt=/path").
# macOS: a Mac app opened through LaunchServices does not start in the current folder: the relative paths
# of existing files become absolute instead.
convertir_args() {
  ARGS=()
  local a cle val
  if [ "$MAC" = 1 ]; then
    for a in "$@"; do
      if [[ "$a" != /* && "$a" != -* ]] && [ -e "$a" ]; then
        ARGS+=("$(pwd)/$a")
      elif [[ "$a" == -*=* && "${a#*=}" != /* ]] && [ -n "${a#*=}" ] && [ -e "${a#*=}" ]; then
        ARGS+=("${a%%=*}=$(pwd)/${a#*=}")
      else
        ARGS+=("$a")
      fi
    done
    return 0
  fi
  for a in "$@"; do
    if [[ "$a" == /* ]] && [ -e "$a" -o -e "$(dirname "$a")" ]; then
      ARGS+=("$(wslpath -w "$a")")
    elif [[ "$a" == -*=/* ]]; then
      cle=${a%%=*}; val=${a#*=}
      if [ -e "$val" ] || [ -e "$(dirname "$val")" ]; then ARGS+=("$cle=$(wslpath -w "$val")"); else ARGS+=("$a"); fi
    else
      ARGS+=("$a")
    fi
  done
}

absent() { echo "$1 is not installed on this PC (or not detected). See .athanor/PC_TOOLS.md." >&2; exit 127; }

# Programs with windows (Unreal, Blender, a game under test) open on Claude's own Windows desktop when the
# option is on in the app (it writes logs/bureau-isole): never on the user's screen, never taking the focus,
# and what they start stays there too. Usage: lancer_windows [--detache] PROGRAM ARGUMENTS...
# Returns the program's exit code (--detache: returns at once, the program keeps running).
lancer_windows() {
  local detache=() prog pid_f p code ici=()
  [ "${1:-}" = "--detache" ] && { detache=(--detache); shift; }
  [ -f "$KIT/logs/bureau-isole" ] || ici=(--ici)
  # Native Windows: a detached program (an editor) goes through Athanor.exe too, which takes it out of the
  # cycle's Windows job: it stays open for the next cycles instead of stopping with this one.
  if [ -x "$KIT/Athanor.exe" ] && { [ ${#ici[@]} -eq 0 ] || { [ "$NATIF" = 1 ] && [ ${#detache[@]} -gt 0 ]; }; }; then
    prog=$1
    [[ "$prog" == */* ]] || prog=$(command -v "$prog" 2>/dev/null || echo "$prog")
    [[ "$prog" == /* ]] && prog=$(wslpath -w "$prog")
    if [ ${#detache[@]} -gt 0 ]; then
      "$KIT/Athanor.exe" --isole "${ici[@]}" --detache -- "$prog" "${@:2}"
      return
    fi
    # A cancelled command (the bridge stops this process group) only stops the Linux side of WSL
    # interop: the Windows process tree is stopped explicitly, from the PID Athanor.exe writes.
    pid_f=$(mktemp -p "$KIT/logs" .isole-XXXXXX)
    "$KIT/Athanor.exe" --isole --pid "$(wslpath -w "$pid_f")" -- "$prog" "${@:2}" &
    p=$!
    trap 'w=$(cat "$pid_f" 2>/dev/null); [[ "$w" =~ ^[0-9]+$ ]] && (cd /mnt/c 2>/dev/null; taskkill.exe /T /F /PID "$w" >/dev/null 2>&1); kill "$p" 2>/dev/null; rm -f "$pid_f"; exit 143' TERM INT HUP
    wait "$p"; code=$?
    trap - TERM INT HUP
    rm -f "$pid_f"
    return "$code"
  fi
  if [ ${#detache[@]} -gt 0 ]; then
    nohup "$@" >/dev/null 2>&1 &
    disown
    return 0
  fi
  "$@"
}

# macOS: a Mac app (APP.app) opens through LaunchServices, in the background (-g: it never takes the focus),
# a new instance each time (-n). With the "Claude's desktop" option (logs/bureau-isole) it also starts
# hidden (-j): macOS gives no other desktop a program can be sent to, a hidden app stays off the user's
# screen until someone shows it. Usage: lancer_mac [--attendre] APP.app ARGUMENTS...
# Returns at once (the app keeps running); --attendre: waits until the app quits, returns its code.
lancer_mac() {
  local o=(-g -n)
  [ "${1:-}" = "--attendre" ] && { o+=(-W); shift; }
  [ -f "$KIT/logs/bureau-isole" ] && o+=(-j)
  local app="$1"; shift
  open "${o[@]}" -a "$app" --args "$@"
}

# macOS: a program downloaded by Claude carries no quarantine, but an unsigned one is refused by macOS on
# Apple chips: it gets an ad hoc signature (local, only valid on this Mac). $1 = file or .app
preparer_mac() {
  xattr -dr com.apple.quarantine "$1" 2>/dev/null
  codesign -v "$1" >/dev/null 2>&1 || codesign -s - -f --deep "$1" >/dev/null 2>&1
  # the application firewall on: the program may receive connections (a game server, a dev server) without
  # the "Accept incoming connections?" window, when the administrator helper is allowed
  case "$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)" in
    *enabled*|*"State = 1"*) executer_admin firewall "$1" >/dev/null 2>&1 ;;
  esac
  return 0
}

# Bridge: inside the sandbox, a gateway cannot start a Windows program or reach Docker.
# It therefore hands the command to the bridge (system/bridge.py, outside the sandbox) and shows its output live.
# Called at the top of every gateway: passer_par_le_pont "$@"
passer_par_le_pont() {
  [ "${PONT_DIRECT:-}" = 1 ] && return 0          # already outside the sandbox: run directly
  local dossier="${ATHANOR_PONT:-$PROJECT/.athanor/pont}" outil id demande sortie code_f vivant i taille=0 nouveau
  outil=$(basename "$0")
  vivant="$dossier/vivant"
  if [ ! -f "$vivant" ] || [ $(( $(date +%s) - $(stat -c %Y "$vivant" 2>/dev/null || echo 0) )) -gt 10 ]; then
    echo "$outil: the pilot's bridge is not responding (pilot stopped?). Restart the pilot." >&2; exit 127
  fi
  id="$(date +%s%N)-$$"; demande="$dossier/demande-$id.json"; sortie="$dossier/sortie-$id.log"; code_f="$dossier/code-$id"
  python3 - "$demande.tmp" "$outil" "$(pwd)" "${UNREAL_MCP_URL:-}" "$@" <<'PY'
import json, sys
f, outil, cwd, mcp, *args = sys.argv[1:]
json.dump({"outil": outil, "cwd": cwd, "args": args, "env": {"UNREAL_MCP_URL": mcp} if mcp else {}}, open(f, "w"))
PY
  mv "$demande.tmp" "$demande"
  trap 'touch "$dossier/annuler-$id"; exit 130' INT TERM
  while :; do
    if [ -f "$sortie" ]; then
      nouveau=$(stat -c %s "$sortie" 2>/dev/null || echo 0)
      if [ "$nouveau" -gt "$taille" ]; then tail -c +"$((taille + 1))" "$sortie" | head -c "$((nouveau - taille))"; taille=$nouveau; fi
    fi
    if [ -f "$code_f" ]; then
      nouveau=$(stat -c %s "$sortie" 2>/dev/null || echo 0)
      [ "$nouveau" -gt "$taille" ] && tail -c +"$((taille + 1))" "$sortie"
      i=$(cat "$code_f"); rm -f "$code_f" "$sortie"; exit "${i:-1}"
    fi
    sleep 0.3
  done
}

# Runs "$@" with administrator rights through the scheduled task "Athanor - installations" (allowed once
# by the user, in the app: Setup & health -> Administrator rights). No UAC prompt. Prints the output, returns the
# exit code; 127 if the task does not exist, 124 if no answer after 20 minutes.
# Usage: executer_admin "C:\path\program.exe" "arg1 arg2"   or   executer_admin WINGET_ID
# macOS: through the administrator helper the user allowed once (commands/allow-admin-mac.sh: a sudo rule
# for /Library/Athanor/athanor-admin alone, no password asked). Usage: executer_admin ACTION PATH
executer_admin() {
  if [ "$MAC" = 1 ]; then
    [ -x /Library/Athanor/athanor-admin ] && sudo -n -l /Library/Athanor/athanor-admin >/dev/null 2>&1 || return 127
    sudo -n /Library/Athanor/athanor-admin "$@"
    return
  fi
  local tache="Athanor - installations" dossier="$KIT/tools/windows/admin-requests" n code
  (cd /mnt/c 2>/dev/null; schtasks.exe /query /tn "$tache" >/dev/null 2>&1) || return 127
  mkdir -p "$dossier"; n="$(date +%s)-$$"
  printf '%s' "$1${2:+ $2}" > "$dossier/demande-$n.txt"
  (cd /mnt/c 2>/dev/null; schtasks.exe /run /tn "$tache" >/dev/null 2>&1)
  for _ in $(seq 1 240); do [ -f "$dossier/resultat-$n.txt" ] && break; sleep 5; done
  if [ -f "$dossier/resultat-$n.txt" ]; then
    tr -d '\r' < "$dossier/resultat-$n.txt" | grep -v '^code='
    code=$(sed -n 's/^code=//p' "$dossier/resultat-$n.txt" | tr -d '\r' | head -n1); rm -f "$dossier/resultat-$n.txt"
    return "${code:-1}"
  fi
  rm -f "$dossier/demande-$n.txt"; echo "No answer from the administrator task after 20 min." >&2; return 124
}
