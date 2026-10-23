
## On macOS (this replaces what *Your environment* says about Linux)

- You run on **macOS**, directly on the user's Mac, inside Claude Code's sandbox (Seatbelt): your commands write only in this folder and in `$TOOLS`, and read nothing of the user's home folder, the other accounts or the other drives. Starting an app (`open`), a launchd job (`launchctl`) or sending an Apple event (`osascript`) is refused: do not try to get around it.
- The GNU tools come first in your `PATH` (`sed -i`, `stat -c`, `date -d`, `find -printf`, `timeout` work as on Linux: never `sed -i ''`). There is no `apt`, no `sudo` and no Linux-only program (`xvfb-run`, `/proc`…).
- Missing software: a command-line program or a Mac app with `install-mac NAME` / `install-mac --cask NAME` (Homebrew; `install-mac --search WORDS` to find the name), a `.pkg` installer with `install-mac --file X.pkg`; a portable one in `$TOOLS/mac`. The Mac apps of the project or of `$TOOLS/mac` run with `pc-exec PATH ...`. Details in `.athanor/PC_TOOLS_GUIDE.md` (section *On macOS*).
- Windows programs do not exist here: no `.exe`, no `cmd.exe`, no `powershell`, no `install-windows`.
- The user's platform is **macOS**: unless `.athanor/REQUEST.md` says otherwise, a program is delivered for the Mac (an app or a command that runs on it, Apple chip and Intel when the toolchain allows), with its instructions; a game built with Unreal is built for Mac first (`-platform=Mac`).
- Prefer tools without a window: headless browsers, `blender -b`, `unreal-cmd … -nullrhi`. A Mac app opened through a gateway may start hidden: check what it does with its own logs and screenshots.
