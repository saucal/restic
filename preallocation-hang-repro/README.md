# A filesystem whose fallocate never returns

Everything here exists to answer one question with evidence rather than argument:
what happens to `restic restore` when the target filesystem accepts the
preallocation syscall and never answers it, and what is the smallest change that
makes restic survive it.

It reproduces, on any machine with Docker, what was first seen on a managed
WordPress host (Pressable), where a restore sat for two hours with no output and
a goroutine dump showed every writer parked in `fallocate`.

Nothing in here ships. It is not part of the fix, and it is deliberately kept on
its own branch so that the fix itself stays a small, reviewable diff.

## The pieces

| Path | What it is |
|---|---|
| `hangfs/` | A FUSE filesystem that mirrors a directory but never answers `fallocate`. Everything else behaves normally. |
| `fsprobe/` | Asks what a caller can still do to a file whose `fallocate` is outstanding: write, truncate, stat, unlink. |
| `scripts/` | The runs described below. Each writes its own log to the work directory. |

## Running it

Build the two helpers for the container's architecture, plus the restic binaries
you want to compare, into one work directory, then mount that directory at
`/work`:

    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "$W/hangfs-linux-arm64" ./hangfs
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "$W/fsprobe-linux-arm64" ./fsprobe
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "$W/restic-upstream" ../cmd/restic   # unpatched
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "$W/restic-final"    ../cmd/restic   # patched

    docker run --rm --cap-add SYS_ADMIN --device /dev/fuse \
        --security-opt apparmor=unconfined -v "$W:/work" -w /work \
        alpine:3.20 sh /work/<script>.sh

`scripts/frag.sh` and `scripts/healthy.sh` need `--privileged` instead, as they
mount a loopback ext4 image.

## What each run establishes

**`repro2.sh <binary> <label> <seconds>` — the failure.** With an unpatched
restic the restore never finishes: SIGQUIT shows the writers in
`createFile` → `ensureSize` → `PreallocateFile` → `unix.Fallocate`, the same
stack as the production dump, and both target files are left at 0 bytes with
nothing printed.

**`probe.sh` — why a deadline cannot rescue it.** While one `fallocate` is
outstanding on a file, the kernel holds that inode, so:

| operation on the wedged file | outcome |
|---|---|
| `pwrite` | blocked |
| `ftruncate` | blocked |
| `fstat` | returns |
| create+write a *different* file | returns |
| `close` | returns |
| `unlink` | blocked — and the directory is then wedged too |

`FALLOC_FL_KEEP_SIZE` behaves identically, so no flag avoids it. A restore that
merely gives up on the call still has one file it can never write, and cannot
clean up after itself.

**`exit2.sh` — why it cannot even be aborted.** After the abandoned call, the
process keeps a thread in `state=D wchan=request_wait_answer`. A thread waiting
on such a filesystem ignores every signal, `SIGKILL` included, so the process
can never be reaped:

    restic pid=61 — STILL ALIVE after the restore finished
      tid 61  state=Z  wchan=0
      tid 75  state=D  wchan=request_wait_answer

This is what rules out any in-process mitigation, and why the fix asks the
question from a process that exists only to ask it.

**`final.sh` — the fix.** The filesystem sees exactly one preallocation, of the
throwaway probe file, and never one for a file being restored. The restore
completes, exits 0, every checksum matches, and nothing is left behind.

**`twice.sh` — repeated runs.** Three restores in a row over the same target,
all exiting 0.

**`healthy.sh` — no regression where it works.** On real ext4 a restored 512 MiB
file comes out in 3 extents, fully allocated, with no warning printed: the
optimization still happens.

**`frag.sh` — what the optimization is worth.** Extent counts and read timings
with and without preallocation on ext4, which is why the fix keeps it rather
than removing it.

## For comparison: rsync

rsync does the same job on the same host without trouble, and its source says
why. `options.c` has `int preallocate_files = 0;` — preallocation is opt-in via
`--preallocate` — and `receiver.c` treats a failure as a warning. It also writes
each file sequentially, so it has far less to gain from reserving space than
restic, which writes blobs out of order. Per `probe.sh`, rsync's choice of
`FALLOC_FL_KEEP_SIZE` would not have saved it here either; not making the call
is what saves it.
