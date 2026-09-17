// fsprobe answers what a caller can still do to a file whose fallocate never returns.
// It decides the shape of any fix: if the kernel serializes on the inode, reacting
// after the call was issued is already too late for that file.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const size = 8 << 20

// try runs op and reports how it ended, giving up on it after 5s.
func try(name string, op func() error) {
	done := make(chan error, 1)
	go func() { done <- op() }()
	select {
	case err := <-done:
		fmt.Printf("    %-34s returned: %v\n", name, err)
	case <-time.After(5 * time.Second):
		fmt.Printf("    %-34s BLOCKED (no answer in 5s)\n", name)
	}
}

func probe(parent string, mode uint32, label string) {
	// Each case gets its own directory: a blocked unlink holds the parent directory's
	// lock, which would otherwise wedge the next case before it starts.
	dir := filepath.Join(parent, "case-"+label)
	if err := os.MkdirAll(dir, 0700); err != nil {
		fmt.Println("  mkdir:", err)
		return
	}
	fmt.Printf("\n== fallocate mode=%s in %s ==\n", label, dir)
	path := filepath.Join(dir, "victim")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		fmt.Println("  open:", err)
		return
	}
	fd := int(f.Fd())

	go func() { // the call that never comes back
		err := unix.Fallocate(fd, mode, 0, size)
		fmt.Printf("    (fallocate itself returned: %v)\n", err)
	}()
	time.Sleep(1500 * time.Millisecond) // let it reach the kernel

	buf := make([]byte, 4096)
	try("pwrite to the same file", func() error { _, err := unix.Pwrite(fd, buf, 0); return err })
	try("ftruncate the same file", func() error { return unix.Ftruncate(fd, size) })
	try("fstat the same file", func() error { var st unix.Stat_t; return unix.Fstat(fd, &st) })
	try("create+write a different file", func() error {
		g, err := os.Create(filepath.Join(dir, "other"))
		if err != nil {
			return err
		}
		defer func() { _ = g.Close() }()
		_, err = g.WriteAt(buf, 0)
		return err
	})
	try("close the wedged file", func() error { return f.Close() })
	// Ordered last: a blocked unlink takes the directory down with it.
	try("unlink the wedged file", func() error { return os.Remove(path) })
	try("create a file after that unlink", func() error {
		g, err := os.Create(filepath.Join(dir, "after-unlink"))
		if err != nil {
			return err
		}
		return g.Close()
	})
}

func main() {
	dir := os.Args[1]
	var st unix.Statfs_t
	if err := unix.Statfs(dir, &st); err == nil {
		fmt.Printf("statfs(%s): type=0x%x bsize=%d\n", dir, st.Type, st.Bsize)
	}
	probe(dir, 0, "zero")
	probe(dir, unix.FALLOC_FL_KEEP_SIZE, "keepsize")
	fmt.Println("\n(the process exits with the stuck calls still outstanding)")
	os.Exit(0)
}
var _ = syscall.Getpid
