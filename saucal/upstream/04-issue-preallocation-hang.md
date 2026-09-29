<!-- NEW ISSUE on restic/restic
     Title: restore hangs, and can't be killed, when fallocate never returns -->

## Output of `restic version`

restic 0.19.1, linux/amd64

## What happens

`restic restore` onto some sandboxed filesystems (seen on managed WordPress hosting) stops at the first file larger than one blob. Files are created empty and nothing further happens. A goroutine dump shows every writer blocked in `fallocate`, via `ensureSize` → `fs.PreallocateFile`.

A timeout doesn't help. Reproduced with a FUSE filesystem that accepts `fallocate` and never replies:

- the kernel holds the inode lock, so `pwrite`, `ftruncate` and `unlink` on that file also block, and a blocked `unlink` blocks its directory;
- the thread is in `D` state (`request_wait_answer`) and ignores `SIGKILL`, so the process can't exit;
- `FALLOC_FL_KEEP_SIZE` behaves the same.

`--sparse` doesn't avoid it: files larger than one blob without zero chunks still preallocate. `restic dump | tar -x` works.

## Proposed fix

Check in a child process whether the filesystem answers `fallocate` before using it, and skip preallocation where it doesn't. PR to follow.
