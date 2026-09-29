<!-- POST AS: a NEW issue
     TITLE:  `restore` hangs forever, and cannot be killed, on a filesystem whose `fallocate` never returns
     BRANCH: none -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

## What happens

`restic restore` onto some sandboxed filesystems — I hit this on managed WordPress
hosting — stops at the first file that needs more than one blob. It creates the
empty files, prints nothing further, and waits. I left one for several hours.

A goroutine dump (`timeout -s QUIT`) shows every writer parked in `fallocate`,
reached from `ensureSize` → `fs.PreallocateFile`. The filesystem accepts the
syscall and never answers it.

`--sparse` is not a workaround: restic marks a file sparse only when it has one
blob or a zero chunk, so anything over about a megabyte still preallocates.
`restic dump | tar -x` does work, being sequential.

## Why a timeout cannot fix it

I built that first. Reproduced against a FUSE filesystem that accepts `fallocate`
and never replies:

- The kernel holds the inode lock for the duration, so `pwrite`, `ftruncate` and
  `unlink` on that file all block indefinitely too — and a blocked `unlink` takes
  its whole directory with it.
- The waiting thread sits in `state=D`, `wchan=request_wait_answer`, and ignores
  `SIGKILL`. The process can never exit.
- `FALLOC_FL_KEEP_SIZE` behaves identically.

So issuing the call is an irreversible commitment. A deadline around it only tells
you that you have already lost that file and that process. This is why #5045's
retry-on-signal approach cannot be extended to cover it: there is no signal to
catch, and the thread would not take one.

## Reproducing it

A FUSE filesystem that answers everything except `fallocate`, which it drops on
the floor, and a restore of any file larger than one blob onto it. I can push that
harness somewhere if it would help.

## What I would like to do about it

Ask the filesystem before relying on it: preallocate a throwaway file whose name is
already unlinked, from a short-lived child process, so a filesystem that never
answers strands that child rather than the restore. Cache the answer per
filesystem. Both existing callers already treat a failed preallocation as harmless,
so where the question goes unanswered the restore simply carries on without
reserving space. Draft pull request to follow.
