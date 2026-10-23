//go:build !windows && !darwin

package main

// Linux: the commands run in the system's own bash, windows in the desktop's terminal, files and links
// open with xdg-open, the autostart entry is the freedesktop one.

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Claude's desktop: a private X server per pilot, whose picture "View" shows (system/ecran.sh)
const (
	marqueBureau  = "xvfb"
	ecranBureau   = true
	messageBureau = "“Claude” screen ready: the Linux windows Claude opens go there, never on your screen."
)

func commandeWSL(k Kit, script string) *exec.Cmd {
	c := exec.Command("bash", "-lc", script)
	c.Dir = k.Racine
	return c
}

// DemarrerDetache: on Linux, the pilot simply goes to the background (setsid in start.sh --background).
func DemarrerDetache(k Kit, script string) error {
	if strings.Contains(script, "--attach") {
		return nil // no WSL to keep awake outside Windows
	}
	c := exec.Command("bash", "-lc", strings.Replace(script, "--keep", "--background", 1))
	c.Dir = k.Racine
	_, err := c.Output()
	return err
}

// FenetreWSL on Linux: the step runs in a terminal window of the desktop (the first one found).
func FenetreWSL(k Kit, titre, script string) error {
	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		return errors.New("Interactive window: no graphical session; run in a terminal: " + script)
	}
	if err := os.MkdirAll(k.Journaux(), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(k.Journaux(), "window-*.sh")
	if err != nil {
		return err
	}
	_, err = f.WriteString("cd " + citerShell(k.Racine) + " || exit 1\n" + script + "\necho\nread -p 'Press Enter to close' _\nrm -f -- \"$0\"\n")
	f.Close()
	if err != nil {
		return err
	}
	for _, t := range [][]string{{"x-terminal-emulator", "-e"}, {"gnome-terminal", "--"}, {"konsole", "-e"}, {"xfce4-terminal", "-x"},
		{"mate-terminal", "-x"}, {"kitty"}, {"alacritty", "-e"}, {"xterm", "-e"}} {
		if chemin, err := exec.LookPath(t[0]); err == nil {
			c := exec.Command(chemin, append(t[1:], "bash", "-l", f.Name())...)
			c.Dir = k.Racine
			return c.Start()
		}
	}
	os.Remove(f.Name())
	return errors.New("Interactive window: no terminal found; run in a terminal: " + script)
}

func Ouvrir(chemin string) error  { return exec.Command("xdg-open", chemin).Start() }
func OuvrirFenetreApp(url string) { _ = exec.Command("xdg-open", url).Start() }

// Linux: "open when the computer starts" = the desktop session's autostart entry
// (~/.config/autostart/athanor.desktop, the freedesktop standard: GNOME, KDE, Xfce, Cinnamon…).
func fichierAutostart() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "autostart", "athanor.desktop")
}

func DemarrageWindows(actif bool) error {
	f := fichierAutostart()
	if f == "" {
		return errors.New("No configuration folder for the autostart entry")
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
	entree := "[Desktop Entry]\nType=Application\nName=Athanor\nComment=Claude Code building whole projects\nExec=\"" +
		strings.ReplaceAll(exe, `"`, `\"`) + "\"\nPath=" + filepath.Dir(exe) + "\nTerminal=false\nX-GNOME-Autostart-enabled=true\n"
	return os.WriteFile(f, []byte(entree), 0o644)
}
func DemarrageWindowsActif() bool {
	_, err := os.Stat(fichierAutostart())
	return err == nil
}
