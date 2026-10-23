//go:build darwin

package main

// The Mac trash: through the Finder, so that "Put Back" restores a deleted project; when the Finder
// cannot be asked (permission refused), straight into ~/.Trash.

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func mettreALaCorbeille(chemin string) error {
	abs, err := filepath.Abs(chemin)
	if err != nil {
		return err
	}
	// the path goes as an argument of the script, never inside its text
	c := exec.Command("osascript", "-e", "on run argv", "-e", `tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)`, "-e", "end run", abs)
	if err := c.Run(); err == nil {
		return nil
	}
	maison, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	corbeille := filepath.Join(maison, ".Trash")
	base := filepath.Base(abs)
	nom := base
	for i := 2; ; i++ {
		if _, err := os.Lstat(filepath.Join(corbeille, nom)); os.IsNotExist(err) {
			break
		}
		nom = fmt.Sprintf("%s %d", base, i)
	}
	if err := os.Rename(abs, filepath.Join(corbeille, nom)); err != nil {
		return errors.New("the folder is on another disk than the trash: delete it yourself")
	}
	return nil
}
