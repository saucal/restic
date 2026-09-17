package diag

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Sampling writes a line as it goes, so a process that is killed still leaves an
// account of what it was using.
func TestStartSamplesToTheFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "diag.log")
	t.Setenv(LogEnv, path)
	t.Setenv(IntervalEnv, "10ms")

	stop := Start()
	time.Sleep(50 * time.Millisecond)
	Record("halfway")
	stop()

	buf, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(buf)), "\n")
	if len(lines) < 3 {
		t.Fatalf("got %d lines, want the start, some samples and the stop:\n%s", len(lines), buf)
	}
	for _, want := range []string{"heap=", "goroutines=", `event="start`, `event="halfway"`, `event="stop"`} {
		if !strings.Contains(string(buf), want) {
			t.Errorf("no %q in the log:\n%s", want, buf)
		}
	}
}

// Without the variable set, restic writes nothing and starts nothing.
func TestStartDoesNothingUnasked(t *testing.T) {
	t.Setenv(LogEnv, "")
	if err := os.Unsetenv(LogEnv); err != nil {
		t.Fatal(err)
	}
	stop := Start()
	defer stop()

	Record("ignored") // must not panic, and must go nowhere
	if out != nil {
		t.Fatal("a file was opened although no diagnostics were asked for")
	}
}
