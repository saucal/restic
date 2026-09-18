// gen builds a synthetic tree shaped like a WordPress uploads directory:
// many small files with long thumbnail-style names. The point of the knobs is
// to separate "many files in one directory" from "many files overall".
package main

import (
	"flag"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
)

func main() {
	root := flag.String("root", "", "directory to fill")
	total := flag.Int("total", 100000, "total number of files")
	perDir := flag.Int("per-dir", 0, "files per directory (0 = all in one directory)")
	size := flag.Int("size", 0, "bytes per file")
	randomNames := flag.Bool("random-names", false, "use incompressible names, so the tree compresses like one whose nodes carry content ids")
	flag.Parse()

	if *root == "" {
		fmt.Fprintln(os.Stderr, "-root is required")
		os.Exit(2)
	}
	per := *perDir
	if per <= 0 {
		per = *total
	}
	// Names as long as the ones WordPress generates for scaled thumbnails,
	// because every name is held in memory while its directory is walked.
	const words = "aluminium-billet-suspension-control-arm-upper-front-driver-side"
	rnd := rand.New(rand.NewSource(1))
	buf := make([]byte, *size)
	for i := range buf {
		buf[i] = byte('a' + rnd.Intn(26))
	}

	dir := ""
	for i := 0; i < *total; i++ {
		if i%per == 0 {
			dir = filepath.Join(*root, fmt.Sprintf("d%05d", i/per))
			if err := os.MkdirAll(dir, 0o755); err != nil {
				panic(err)
			}
		}
		name := fmt.Sprintf("%s-%07d-%dx%d.jpg", words, i, 150+i%900, 150+i%700)
		if *randomNames {
			var r [24]byte
			rnd.Read(r[:])
			name = fmt.Sprintf("%x-%07d.jpg", r, i)
		}
		if err := os.WriteFile(filepath.Join(dir, name), buf, 0o644); err != nil {
			panic(err)
		}
	}
	fmt.Printf("wrote %d files, %d per dir, %d bytes each\n", *total, per, *size)
}
