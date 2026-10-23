//go:build !windows

package main

// Linux or macOS (native kit, or code checking): same functions, without WSL or virtual desktop.
// What differs between the two: systeme_linux.go, systeme_darwin.go.

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
)

func cacherFenetre(c *exec.Cmd) {}

func FenetrePowerShell(k Kit, s string) error { return errors.New("PowerShell: Windows only") }
func FenetreApp(url string) bool              { return false }

// Linux: the window is the browser's (no notification area icon); a second launch opens another one.
func permettrePremierPlan()                                               {}
func montrerFenetre()                                                     { OuvrirFenetreApp(lienApp()) }
func IconeNotification(langue func() string, ouvrir, quitter func()) bool { return false }

func migrerSysteme() {}

// Bureau on Linux: Claude's desktop is the private X server each pilot runs (system/ecran.sh); on macOS,
// the Mac apps the gateways open start hidden. The option only writes or removes logs/bureau-isole, which
// the pilots read at every cycle; on Linux "View" opens the picture of that screen in the application
// (GET /api/ecran).
type Bureau struct {
	mu            sync.Mutex
	kit           Kit
	Programmes    []string
	Actif         bool
	PilotesActifs func() bool
	Langue        func() string
}
type EtatBureau struct {
	Disponible bool     `json:"disponible"`
	Message    string   `json:"message"`
	Deplacees  int      `json:"deplacees"`
	Vues       []string `json:"vues"`
	Isole      bool     `json:"isole"`
	Restantes  int      `json:"restantes"`
	Ecran      bool     `json:"ecran"` // Linux: "View" shows Claude's screen in the application
}

func NouveauBureau(k Kit) *Bureau {
	b := &Bureau{kit: k, Actif: true}
	b.marquer()
	return b
}
func (b *Bureau) DefinirKit(k Kit) {
	b.mu.Lock()
	ancien := b.kit.Racine
	b.kit = k
	b.mu.Unlock()
	if ancien != "" && ancien != k.Racine { // the previous tool folder's pilots go back to the user's screen
		os.Remove(filepath.Join(ancien, "logs", "bureau-isole"))
	}
	b.marquer()
}
func (b *Bureau) DefinirDossiers(d []string) {}
func (b *Bureau) DefinirReglages(actif bool, programmes []string) {
	b.mu.Lock()
	b.Actif, b.Programmes = actif, programmes
	b.mu.Unlock()
	b.marquer()
}

// marquer writes or removes logs/bureau-isole in the tool folder (read by the pilots at every cycle).
func (b *Bureau) marquer() {
	b.mu.Lock()
	racine, actif := b.kit.Racine, b.Actif
	b.mu.Unlock()
	if racine == "" {
		return
	}
	f := filepath.Join(racine, "logs", "bureau-isole")
	if !actif {
		os.Remove(f)
		return
	}
	os.MkdirAll(filepath.Dir(f), 0o755)
	os.WriteFile(f, []byte(marqueBureau+"\n"), 0o644)
}

func (b *Bureau) Etat() EtatBureau {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.Actif {
		return EtatBureau{Message: "Virtual desktop disabled (Options).", Ecran: ecranBureau}
	}
	return EtatBureau{Disponible: true, Ecran: ecranBureau, Message: messageBureau}
}
func (b *Bureau) Voir() error        { return errors.New("Windows only") }
func (b *Bureau) Revenir() error     { return errors.New("Windows only") }
func (b *Bureau) RamenerTout() error { return errors.New("Windows only") }

// LancerIsole (Athanor.exe --isole): Claude's isolated desktop exists on Windows only.
func LancerIsole(args []string) int {
	fmt.Fprintln(os.Stderr, "--isole: Windows only")
	return 2
}

func remettreBureau() {}

func GardienRetour(args []string) int { return 2 }

// lancerDetache (athanor --lancer ARGS): starts the application itself in a session of its own, without a
// terminal, and returns at once: it outlives Athanor.app's launcher (system/macres/empaqueter.sh).
func lancerDetache(args []string) int {
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	c := exec.Command(exe, args...)
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := c.Start(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

// arreterArbre stops a command (its own process; the script's timeout bounds the rest).
func arreterArbre(c *exec.Cmd) {
	if c != nil && c.Process != nil {
		_ = c.Process.Kill()
	}
}
