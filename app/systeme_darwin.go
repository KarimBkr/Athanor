//go:build darwin

package main

// macOS: the commands run in Homebrew's bash (the scripts need Bash 4 or later, macOS ships 3.2), with
// Homebrew and Claude Code in the PATH (an app opened from the Finder gets a bare PATH); windows open in
// Terminal, files and links with open, the application window in a browser's app mode; the autostart
// entry is a LaunchAgent.

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Claude's desktop: the Mac apps the gateways open start hidden and in the background (system/bin/_common.sh)
const (
	marqueBureau  = "mac"
	ecranBureau   = false
	messageBureau = "The Mac apps Claude opens start hidden and in the background: they never take your screen or the focus."
)

// bashMac: Homebrew's bash (Apple chip, then Intel), else the system's (the scripts then say what is missing).
func bashMac() string {
	for _, b := range []string{"/opt/homebrew/bin/bash", "/usr/local/bin/bash"} {
		if st, err := os.Stat(b); err == nil && !st.IsDir() {
			return b
		}
	}
	return "/bin/bash"
}

// environnementMac: the user's environment, with Homebrew and Claude Code (~/.local/bin) first in the PATH.
func environnementMac() []string {
	maison, _ := os.UserHomeDir()
	chemin := strings.Join([]string{"/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", filepath.Join(maison, ".local", "bin"),
		os.Getenv("PATH"), "/usr/bin", "/bin", "/usr/sbin", "/sbin"}, ":")
	env := []string{}
	for _, v := range os.Environ() {
		if !strings.HasPrefix(v, "PATH=") {
			env = append(env, v)
		}
	}
	return append(env, "PATH="+chemin)
}

// (no login shell: macOS's /etc/profile would put /bin, and its Bash 3.2, back before Homebrew)
func commandeWSL(k Kit, script string) *exec.Cmd {
	c := exec.Command(bashMac(), "-c", script)
	c.Dir = k.Racine
	c.Env = environnementMac()
	return c
}

// DemarrerDetache: the pilot goes to the background (setsid in start.sh --background) and survives the app.
func DemarrerDetache(k Kit, script string) error {
	if strings.Contains(script, "--attach") {
		return nil // no WSL to keep awake outside Windows
	}
	c := commandeWSL(k, strings.Replace(script, "--keep", "--background", 1))
	_, err := c.Output()
	return err
}

// FenetreWSL on macOS: the step runs in a Terminal window (a .command file, which Terminal runs when it opens it).
func FenetreWSL(k Kit, titre, script string) error {
	if err := os.MkdirAll(k.Journaux(), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(k.Journaux(), "window-*.command")
	if err != nil {
		return err
	}
	_, err = f.WriteString("#!" + bashMac() + " -l\nexport PATH=\"/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH\"\nprintf '\\033]0;%s\\007' " +
		citerShell("Athanor: "+titre) + "\ncd " + citerShell(k.Racine) + " || exit 1\nrm -f -- \"$0\"\n" + script + "\necho\nread -p 'Press Enter to close' _\n")
	f.Close()
	if err != nil {
		os.Remove(f.Name())
		return err
	}
	if err := os.Chmod(f.Name(), 0o700); err != nil {
		os.Remove(f.Name())
		return err
	}
	if err := exec.Command("open", "-a", "Terminal", f.Name()).Start(); err != nil {
		os.Remove(f.Name())
		return errors.New("Interactive window: Terminal does not open; run in a terminal: " + script)
	}
	return nil
}

func Ouvrir(chemin string) error { return exec.Command("open", chemin).Start() }

// OuvrirFenetreApp: a window of its own (a browser's app mode: no tabs, no address bar) when a Chromium
// browser is installed, else a tab of the default browser.
func OuvrirFenetreApp(url string) {
	maison, _ := os.UserHomeDir()
	for _, nom := range []string{"Google Chrome", "Microsoft Edge", "Brave Browser", "Chromium", "Vivaldi"} {
		for _, d := range []string{"/Applications", filepath.Join(maison, "Applications")} {
			if _, err := os.Stat(filepath.Join(d, nom+".app")); err == nil {
				if exec.Command("open", "-na", filepath.Join(d, nom+".app"), "--args", "--app="+url).Start() == nil {
					return
				}
			}
		}
	}
	_ = exec.Command("open", url).Start()
}

// "Open when the computer starts" = a LaunchAgent of the user (~/Library/LaunchAgents/com.athanor.app.plist).
func fichierAutostart() string {
	maison, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(maison, "Library", "LaunchAgents", "com.athanor.app.plist")
}

func DemarrageWindows(actif bool) error {
	f := fichierAutostart()
	if f == "" {
		return errors.New("No home folder for the LaunchAgent")
	}
	if !actif {
		if err := os.Remove(f); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
		return err
	}
	x := func(s string) string {
		return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;").Replace(s)
	}
	// AbandonProcessGroup: the pilots the app starts keep running when it quits
	plist := `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.athanor.app</string>
	<key>ProgramArguments</key><array><string>` + x(exe) + `</string></array>
	<key>WorkingDirectory</key><string>` + x(filepath.Dir(exe)) + `</string>
	<key>RunAtLoad</key><true/>
	<key>AbandonProcessGroup</key><true/>
	<key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
`
	return os.WriteFile(f, []byte(plist), 0o644)
}
func DemarrageWindowsActif() bool {
	_, err := os.Stat(fichierAutostart())
	return err == nil
}
