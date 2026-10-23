#!/bin/bash
# =============================================================================
#  Athanor (macOS): installation, to run once (and again whenever a check fails).
#  Installs with Homebrew: Bash 4 or later, the GNU tools the scripts use (coreutils, findutils, sed,
#  flock), git, jq, ripgrep, python, node, ImageMagick, ffmpeg, the GitHub CLI (zip and ssh come with macOS); then Pillow, Claude Code
#  and RTK. Claude's sandbox is Claude Code's own on macOS (Seatbelt): nothing to install for it.
#  Homebrew must be installed first (https://brew.sh); it may ask for your password.
#  (Starts in the Bash of macOS, 3.2: nothing newer is used here.)
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1
KIT=$(pwd); SYSTEME="$KIT/system"
mkdir -p "$KIT/logs"; exec > >(tee -a "$KIT/logs/install-mac.log") 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') install-mac.sh (macOS $(sw_vers -productVersion), $(uname -m))"
VERT=$'\033[32m'; JAUNE=$'\033[33m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
etape() { printf '\n%s== %s%s\n' "$GRAS" "$1" "$FIN"; }
ok()    { printf '%s✓ %s%s\n' "$VERT" "$1" "$FIN"; }
alerte(){ printf '%s! %s%s\n' "$JAUNE" "$1" "$FIN"; }

[ "$(uname -s)" = Darwin ] || { echo "This script is for macOS (Linux: commands/install.sh)."; exit 2; }

etape "Homebrew"
BREW=""; for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && { BREW=$b; break; }; done
if [ -z "$BREW" ]; then
  alerte "Homebrew is not installed. Install it first (it asks for your password), then run this script again:"
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
eval "$("$BREW" shellenv)"
ok "Homebrew $("$BREW" --version | head -n 1 | cut -d' ' -f2)"

etape "Packages"
# what is already installed stays at its version (an upgrade here could break the user's other tools);
# a program left pointing at a library another install replaced is reinstalled below
export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_UPGRADE=1
"$BREW" install bash coreutils findutils gnu-sed flock git jq ripgrep python node imagemagick ffmpeg gh \
  && ok "Packages installed" || alerte "Package installation incomplete: read the messages above."
for p in ffmpeg magick; do "$p" -version >/dev/null 2>&1 || { "$BREW" reinstall "$(echo "$p" | sed 's/magick/imagemagick/')" >/dev/null 2>&1 && ok "$p repaired"; }; done

etape "Python: Pillow (screenshot boards)"
PY="$(brew --prefix)/bin/python3"
if "$PY" -c 'import PIL' 2>/dev/null; then ok "Pillow already present"
elif "$BREW" install pillow >/dev/null 2>&1 || "$PY" -m pip install --user --break-system-packages -q Pillow; then ok "Pillow installed"
else alerte "Pillow not installed: the screenshot boards will be unavailable."; fi

etape "Claude Code"
export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
  claude update >/dev/null 2>&1
  ok "Claude Code $(claude --version 2>/dev/null | head -n1)"
else
  curl -fsSL https://claude.ai/install.sh | bash && ok "Claude Code installed" || alerte "Claude Code installation failed."
fi
for f in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  grep -q '.local/bin' "$f" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$f"
done

etape "RTK (command output compression)"
RTK_VERSION=v0.50.0
case "$(uname -m)" in arm64) cible=aarch64-apple-darwin ;; x86_64) cible=x86_64-apple-darwin ;; *) cible="" ;; esac
if [ -x "$SYSTEME/bin/rtk" ] && "$SYSTEME/bin/rtk" --version >/dev/null 2>&1; then ok "RTK already present"
elif [ -n "$cible" ] && curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/$RTK_VERSION/rtk-$cible.tar.gz" | tar -xz -C "$SYSTEME/bin" rtk; then
  xattr -d com.apple.quarantine "$SYSTEME/bin/rtk" 2>/dev/null; ok "RTK $RTK_VERSION installed"
else alerte "RTK not installed: Claude will work without it."; fi

etape "System sandbox"
if sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then ok "Seatbelt available (Claude Code's sandbox on macOS)"
else alerte "Seatbelt does not start: Claude will refuse to start."; fi

etape "Docker (optional, for \"tool IMAGE COMMAND\")"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ok "Docker reachable"
else alerte "Docker unreachable: install and start Docker Desktop if your projects need it."; fi

etape "Mac tools"
chmod +x "$KIT"/commands/*.sh "$SYSTEME"/*.sh "$SYSTEME"/bin/* "$SYSTEME"/mac/* 2>/dev/null
mkdir -p "$KIT/tools/mac"
PROJECT="$KIT/logs/sandbox-test" "$(brew --prefix)/bin/bash" "$SYSTEME/detect-tools.sh"; sed -n '3,20p' "$KIT/logs/sandbox-test/.athanor/PC_TOOLS.md"

etape "Done"
echo "Next step: configure (token, model...): in the app (Settings), or commands/configure.sh"
echo "Then, to test the sandbox: commands/test-sandbox.sh (Setup & health -> Test the sandbox)"
echo "Optional: administrator rights for the .pkg installers: commands/allow-admin-mac.sh"
