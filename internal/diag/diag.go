// Package diag records what restic is costing in memory while it runs.
//
// It exists for backups that are killed rather than failed: the kernel's OOM killer
// sends SIGKILL, which cannot be caught, so the only account of what happened is one
// written as it happens. Each sample is therefore flushed as it is taken, and the last
// line of the file is what restic was using when it died.
//
// For the same reason the file usually has no closing line: restic ends by calling
// os.Exit, which runs no deferred functions. Read the last sample as the end of the
// run, whether that run finished or was killed.
package diag

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// LogEnv names the file to write to, and IntervalEnv how often to sample it.
const (
	LogEnv      = "RESTIC_DIAG_LOG"
	IntervalEnv = "RESTIC_DIAG_INTERVAL"
)

const defaultInterval = 10 * time.Second

var (
	mu  sync.Mutex
	out *os.File
)

// Start begins sampling if LogEnv names a file, and returns the function that stops
// it. Without that variable set, nothing is written and nothing is sampled.
func Start() (stop func()) {
	path := os.Getenv(LogEnv)
	if path == "" {
		return func() {}
	}

	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cannot write diagnostics to %v: %v\n", path, err)
		return func() {}
	}

	mu.Lock()
	out = f
	mu.Unlock()

	Record("start pid=" + strconv.Itoa(os.Getpid()) + " args=" + strings.Join(os.Args[1:], " "))

	done := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		ticker := time.NewTicker(interval())
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				Record("")
			case <-done:
				Record("stop")
				return
			}
		}
	}()

	return func() {
		close(done)
		wg.Wait()
		mu.Lock()
		defer mu.Unlock()
		_ = out.Close()
		out = nil
	}
}

// Record writes one line: the current memory figures, and event if it is not empty.
// It is safe to call whether or not sampling was started.
func Record(event string) {
	mu.Lock()
	defer mu.Unlock()
	if out == nil {
		return
	}

	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	line := fmt.Sprintf("%s heap=%d heap_sys=%d sys=%d gc=%d goroutines=%d",
		time.Now().UTC().Format(time.RFC3339), m.HeapAlloc, m.HeapSys, m.Sys, m.NumGC, runtime.NumGoroutine())

	// What the OOM killer actually watches, where a cgroup says so. Go's own figures
	// do not include what the kernel counts against the process.
	if used, ok := cgroupValue("/sys/fs/cgroup/memory.current", "/sys/fs/cgroup/memory/memory.usage_in_bytes"); ok {
		line += " cgroup_used=" + used
	}
	if max, ok := cgroupValue("/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory/memory.limit_in_bytes"); ok {
		line += " cgroup_max=" + max
	}
	if event != "" {
		line += " event=" + strconv.Quote(event)
	}

	// Written and flushed one line at a time: a killed process keeps what it had.
	_, _ = out.WriteString(line + "\n")
	_ = out.Sync()
}

func interval() time.Duration {
	if s := os.Getenv(IntervalEnv); s != "" {
		if d, err := time.ParseDuration(s); err == nil && d > 0 {
			return d
		}
		fmt.Fprintf(os.Stderr, "ignoring %s=%q: not a duration like 10s\n", IntervalEnv, s)
	}
	return defaultInterval
}

// cgroupValue reads the first of paths that holds a value, trying cgroup v2 before v1.
func cgroupValue(paths ...string) (string, bool) {
	for _, p := range paths {
		buf, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		if v := strings.TrimSpace(string(buf)); v != "" {
			return v, true
		}
	}
	return "", false
}
