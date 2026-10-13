//go:build !linux && !darwin

package fs

import "os"

// preallocateFile is the platform's own call (windows: SetEndOfFile via truncate);
// PreallocateFile in preallocate.go only makes it once the filesystem has answered.
func preallocateFile(wr *os.File, size int64) error {
	// Maybe truncate can help?
	// Windows: This calls SetEndOfFile which preallocates space on disk
	return wr.Truncate(size)
}
