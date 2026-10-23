#!/bin/bash -p
# Runs a local MCP server (stdio) in a cage (bubblewrap), the way Claude's own commands run in the
# system sandbox. Inside: the system read-only, the project folder writable, the tool caches (tools/)
# writable, the network. Hidden: the user's home (except the toolchains: nvm, uv, cargo…), the Windows
# drives (/mnt), Athanor's folder and its secrets, the WSL bridge to Windows. The Claude token never
# reaches the server.
#
# Usage: mcp-jail.sh NAME TOOLS [--rw DIR]... [--ro DIR]... [--env NAME VALUE]... -- COMMAND [ARGS...]
# The server's variables come as --env (set inside the cage only): this script runs outside the cage, so
# its own environment is never taken from a server's configuration (-p: no BASH_ENV, no imported functions).
# (written into the MCP configuration by system/extensions.py; never called by hand)
set -u
# macOS: the cage is Seatbelt (sandbox-exec), and this script needs Bash 4 or later
MAC=0
if [ "$(uname -s)" = Darwin ]; then
  MAC=1
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [ -x "$b" ] && exec "$b" -p "$0" "$@"; done
    echo "mcp-jail: Bash 4 or later is missing (brew install bash)" >&2; exit 1
  fi
fi
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin   # bwrap is found here, never elsewhere
[ "$MAC" = 1 ] && export PATH="/opt/homebrew/bin:$PATH"                   # node, uv: Homebrew's
unset LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT GCONV_PATH
nom="${1:-}"; outils="${2:-}"; shift 2 2>/dev/null || { echo "mcp-jail: usage: NAME TOOLS [--rw DIR]... -- COMMAND" >&2; exit 2; }
ecriture=(); lecture=(); variables=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  case "$1" in
    --rw) ecriture+=("$2"); shift 2 ;;
    --ro) lecture+=("$2"); shift 2 ;;
    --env) [[ "${2:-}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,127}$ ]] || { echo "mcp-jail: invalid variable" >&2; exit 2; }
           variables+=(--setenv "$2" "${3-}"); shift 3 ;;
    *) echo "mcp-jail: unknown option $1" >&2; exit 2 ;;
  esac
done
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "mcp-jail: no command" >&2; exit 2; }
[[ "$nom" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || { echo "mcp-jail: invalid name" >&2; exit 2; }
[ -d "$outils" ] || { echo "mcp-jail: tool folder not found" >&2; exit 2; }

if [ "$MAC" = 1 ]; then
  # A Seatbelt profile (sandbox-exec, what Claude Code's sandbox uses on macOS), written fresh at each start
  # in the kit's logs/ (out of the server's reach). As with bubblewrap: the project folders and tools/
  # writable, the user's home hidden except the toolchains, the other drives and accounts hidden, the
  # network open; and no way out through macOS (opening an app, an Apple event, a launchd job). The
  # server's variables are set inside the cage, by the shell started there: never in this script's own
  # environment, which runs outside it.
  maison="$outils/mcp/$nom"
  mkdir -p "$maison/tmp" "$outils/cache/npm" "$outils/cache/uv" || exit 1
  regles="$(dirname "$outils")/logs/mcp-cages"; mkdir -p "$regles" || exit 1
  ligne=$(python3 -I - "$regles/$nom.sb" "$HOME" "$outils" "$maison" "${#ecriture[@]}" "${ecriture[@]}" "${#lecture[@]}" "${lecture[@]}" "${variables[@]}" -- "$@" <<'PY'
import os, shlex, sys
a = sys.argv[1:]
regles, maison_vraie, outils, maison = a[:4]; a = a[4:]
n = int(a[0]); ecriture = a[1:1 + n]; a = a[1 + n:]
n = int(a[0]); lecture = a[1:1 + n]; a = a[1 + n:]
i = a.index("--"); variables, commande = a[:i], a[i + 1:]
reel = lambda d: os.path.realpath(d)
q = lambda d: '"' + reel(d).replace("\\", "\\\\").replace('"', '\\"') + '"'
chaines = [os.path.join(maison_vraie, d) for d in (".nvm", ".volta", ".bun", ".deno", ".cargo", ".npm-global",
           ".local/bin", ".local/share/uv", ".local/share/pnpm", ".local/pipx", ".pyenv")]
ecrire = [d for d in ecriture if os.path.isdir(d)] + [outils, maison]
lire = [d for d in chaines + lecture if os.path.isdir(d)] + ecrire
profil = ["(version 1)", "(allow default)",
          # hidden: the home, the other accounts, the other drives (metadata stays readable: paths resolve)
          "(deny file-read-data (subpath %s) (subpath \"/Users\") (subpath \"/Volumes\"))" % q(maison_vraie),
          "(allow file-read-data %s)" % " ".join("(subpath %s)" % q(d) for d in lire),
          "(deny file-write* (subpath \"/\"))",
          "(allow file-write* %s (subpath \"/private/tmp\") (subpath \"/dev\"))" % " ".join("(subpath %s)" % q(d) for d in ecrire),
          # no way out of the cage through macOS: LaunchServices, Apple events, launchd jobs
          "(deny lsopen)", "(deny appleevent-send)",
          "(deny mach-lookup (global-name \"com.apple.coreservices.launchservicesd\") (global-name \"com.apple.coreservices.appleevents\"))",
          "(deny process-exec (literal \"/usr/bin/open\") (literal \"/usr/bin/osascript\") (literal \"/bin/launchctl\"))"]
with open(regles, "w", encoding="utf-8") as f:
    f.write("\n".join(profil) + "\n")
env = {}
for j in range(0, len(variables), 3):   # --setenv NAME VALUE, the form built above
    env[variables[j + 1]] = variables[j + 2]
env.update(HOME=maison, TMPDIR=os.path.join(maison, "tmp"), XDG_CACHE_HOME=os.path.join(outils, "cache"),
           npm_config_cache=os.path.join(outils, "cache", "npm"), UV_CACHE_DIR=os.path.join(outils, "cache", "uv"),
           PLAYWRIGHT_BROWSERS_PATH=os.path.join(outils, "cache", "ms-playwright"))
dossier = ecrire[0] if ecriture else maison
print("cd %s && %sexec %s" % (shlex.quote(dossier), "".join("export %s=%s; " % (k, shlex.quote(v)) for k, v in env.items()),
                              " ".join(shlex.quote(x) for x in commande)))
PY
) || exit 1
  unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
  exec /usr/bin/sandbox-exec -f "$regles/$nom.sb" /bin/bash -c "$ligne"
fi
command -v bwrap > /dev/null || { echo "mcp-jail: bubblewrap is missing (run install)" >&2; exit 1; }

maison="$outils/mcp/$nom"
mkdir -p "$maison" "$outils/cache/npm" "$outils/cache/uv" || exit 1

a=(--ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /mnt)
[ -d /run/WSL ] && a+=(--tmpfs /run/WSL)               # no launching Windows programs through WSL interop
# Name resolution: WSL links /etc/resolv.conf (and sometimes hosts) into /mnt/wsl, hidden above; the
# files themselves come back, read-only, so the server can still reach the network.
for f in /etc/resolv.conf /etc/hosts /etc/nsswitch.conf; do
  r=$(readlink -f "$f" 2>/dev/null) || continue
  case "$r" in /mnt/*) [ -f "$r" ] && a+=(--ro-bind "$r" "$r") ;; esac
done
[ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ "$HOME" != / ] && {
  a+=(--tmpfs "$HOME")
  # the toolchains installed in the home stay usable (read-only): npx, uvx, node from nvm…
  for d in .nvm .volta .bun .deno .cargo .npm-global .local/bin .local/share/uv .local/share/pnpm .local/pipx .pyenv; do
    [ -d "$HOME/$d" ] && a+=(--ro-bind "$HOME/$d" "$HOME/$d")
  done
}
for d in "${lecture[@]}"; do [ -d "$d" ] && a+=(--ro-bind "$d" "$d"); done
for d in "${ecriture[@]}"; do [ -d "$d" ] && a+=(--bind "$d" "$d"); done
a+=(--bind "$outils" "$outils")
# Claude's screen (system/ecran.sh): a server's windows (Godot, a browser) open there, never on the user's screen.
[ -n "${ATHANOR_X11_DIR:-}" ] && [ -d "$ATHANOR_X11_DIR" ] && a+=(--bind "$ATHANOR_X11_DIR" /tmp/.X11-unix)
a+=("${variables[@]}")   # the server's own variables, before the cage's (HOME, caches…) which win
a+=(--setenv HOME "$maison" --setenv XDG_CACHE_HOME "$outils/cache" --setenv npm_config_cache "$outils/cache/npm"
    --setenv UV_CACHE_DIR "$outils/cache/uv" --setenv PLAYWRIGHT_BROWSERS_PATH "$outils/cache/ms-playwright"
    --unsetenv CLAUDE_CODE_OAUTH_TOKEN --unsetenv ANTHROPIC_API_KEY --unsetenv WSL_INTEROP
    --die-with-parent --chdir "${ecriture[0]:-$maison}")
exec bwrap "${a[@]}" -- "$@"
