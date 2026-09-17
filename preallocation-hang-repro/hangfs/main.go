// hangfs mirrors a directory, but its fallocate never returns.
//
// It reproduces what restic hits on Pressable: a filesystem that accepts the
// preallocation syscall and then never answers it. Everything else behaves
// normally, so a restore into this mount fails exactly where the real one does.
//
//	hangfs <backing dir> <mountpoint> [hang seconds, default: forever]
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"
)

var hangFor time.Duration // 0 means forever

type hangNode struct {
	fs.LoopbackNode
}

var _ = (fs.NodeAllocater)((*hangNode)(nil))

func (n *hangNode) Allocate(ctx context.Context, f fs.FileHandle, off, size uint64, mode uint32) syscall.Errno {
	fmt.Fprintf(os.Stderr, "hangfs: fallocate(off=%d, size=%d, mode=%d) — not answering\n", off, size, mode)
	if hangFor == 0 {
		select {} // the call never returns, like the real thing
	}
	time.Sleep(hangFor)
	return 0
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: hangfs <backing dir> <mountpoint> [hang seconds]")
		os.Exit(2)
	}
	backing, mnt := os.Args[1], os.Args[2]
	if len(os.Args) > 3 {
		s, err := strconv.Atoi(os.Args[3])
		if err != nil {
			panic(err)
		}
		hangFor = time.Duration(s) * time.Second
	}

	rootData := &fs.LoopbackRoot{Path: backing}
	rootData.NewNode = func(_ *fs.LoopbackRoot, _ *fs.Inode, _ string, _ *syscall.Stat_t) fs.InodeEmbedder {
		return &hangNode{fs.LoopbackNode{RootData: rootData}}
	}
	root := &hangNode{fs.LoopbackNode{RootData: rootData}}

	server, err := fs.Mount(mnt, root, &fs.Options{
		MountOptions: fuse.MountOptions{DirectMount: true, FsName: "hangfs", Name: "hangfs"},
	})
	if err != nil {
		panic(err)
	}
	fmt.Fprintf(os.Stderr, "hangfs: mounted %s on %s\n", backing, mnt)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-stop; _ = server.Unmount() }()
	server.Wait()
}
