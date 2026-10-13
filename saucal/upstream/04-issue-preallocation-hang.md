<!-- NEW ISSUE on restic/restic
     Title: restore hangs, and can't be killed, when fallocate never returns -->

## Output of `restic version`

restic 0.19.1, linux/amd64

## What happens

On some filesystems `fallocate` can be accepted and never return. `restic restore` then stops at the first file larger than one blob. Files are created empty and nothing further happens. A goroutine dump shows every writer blocked in `fallocate`, via `ensureSize` → `fs.PreallocateFile`.

A timeout doesn't help. Reproduced with a FUSE filesystem that accepts `fallocate` and never replies:

- the kernel holds the inode lock, so `pwrite`, `ftruncate` and `unlink` on that file also block, and a blocked `unlink` blocks its directory;
- the thread is in `D` state (`request_wait_answer`) and ignores `SIGKILL`, so the process can't exit;
- `FALLOC_FL_KEEP_SIZE` behaves the same.

Preallocation is only an optimisation: the file can be written without it. But `--sparse` doesn't skip it for files larger than one blob without zero chunks, and nothing else lets restore avoid the call. `restic dump | tar -x` works.

## Proposed fix

Since the file can be written without preallocating, check in a child process whether the filesystem answers `fallocate` before calling it for a file, and skip preallocation where it doesn't. PR to follow.
