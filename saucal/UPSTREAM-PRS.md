# What we are proposing upstream, and in what words

Four pull requests and two issues, drafted here before anything is posted. Each
branch is built on `restic/restic` master and carries no reference to this fork,
to saucal, to any client, or to how the code was written — acknowledging that
belongs in the pull request's own words, not in a commit trailer. No session
links anywhere.

Post in this order. The first two stand alone; the third is only worth a
maintainer's time once they have accepted the first two.

| order | branch | shape |
| ----- | ------ | ----- |
| 1 | `upstream/pr1-bound-pending-nodes` | 1 commit, archiver only, no interface change |
| 2 | `upstream/pr2-verify-large-blob` | 1 commit, repository only |
| 3 | `upstream/pr3-spill-wide-tree` | stacked on 1 and 2; adds one interface method |
| 4 | `upstream/pr4-preallocation-guard` | 1 commit, independent of the others |

Not proposed:

- **The minio CI change.** Obsolete. Upstream hit the same dead download and
  fixed it differently in #22067, merged 2026-09-20, replacing minio with
  seaweedfs. Branch deleted.
- **`upstream/resource-diagnostics`.** Our own instrumentation. It would need a
  design conversation about a `--diag` surface nobody has asked for, and the
  branch has 40 MB of built binaries committed to `dist/` by accident. If it
  ever goes up, it needs rebuilding from scratch.

## State of the four branches, as of 2026-09-25

All four rebased onto `restic/restic` master at `6adedec6b`, which is newer than
the base they were developed and released on — it includes a klauspost/compress
bump to 1.20.0, which the zstd code in pull requests 2 and 3 uses. On that base,
each branch: builds, is `gofmt` clean, passes `golangci-lint run
--new-from-rev=upstream/master` with 0 issues, and passes the test suite. A full
`go test ./...` on pull request 3 fails exactly the six tests that also fail on
unmodified master in this environment (`TestMount`, `TestMountSameTimestamps`,
`TestStdinFromCommand`, `TestStdinFromCommandNoOutput`, `TestNodeRestoreAt`,
`TestOverwriteXattr` — no OSXFUSE, macOS xattr behaviour) and nothing else.

Pull request 3's code is byte for byte the code that went through the full CI
matrix and has been running on the real host since; the only differences between
that branch and this one are files upstream itself changed and we do not touch.

## Before posting each one

1. Open the issue first. Restic's `CONTRIBUTING.md` asks for that for anything
   that is not a small bugfix, and the changelog filename wants the issue number.
2. Rename `changelog/unreleased/pull-9999N` to `issue-<the real number>`, fix the
   URL on its last line, and amend. The placeholder numbers exist only so the
   file has a name.
3. Push the branch to `saucal/restic` and open the PR from there against
   `restic/restic:master`, with maintainer edits enabled.
4. In the template's checklist, tick tests, changelog and ready-for-review. The
   documentation box does not apply to any of these.

## The note that ends every pull request body

Verbatim, at the end of the first section. It is the whole of the disclosure: no
footnotes, no attribution trailers, no links to anything but restic and the
harness.

> **How this was written.** I should be upfront about two things. I am not a Go
> developer — I came to this from the operations side, after production backups
> started failing — and the code was written with heavy use of an AI coding
> assistant, read and measured by me at each step. Every number above I measured
> myself, before and after, on the harness linked here; the change passes the
> existing test suite along with the tests added here, and it has been running on
> real backups of the site that prompted it. What I cannot vouch for is that it
> reads the way a regular contributor's patch would, so please review it as a
> patch from an outsider to this codebase. I would much rather rework it than
> have you inherit something subtly wrong.

---

# Issue A — for pull requests 1, 2 and 3

**Title:** Backing up one directory with a very large number of entries costs
about a kilobyte of memory per entry

**Body:**

## What happens

On a host that caps the memory a process may use, `restic backup` is killed when
a single directory holds a few hundred thousand entries. What sent me looking is
a WordPress uploads directory of about 1.14M files on managed hosting that kills
a process at roughly 680 MB; it had not completed a backup for months. The
snapshot is not large — 51 GiB, and the files barely change.

The cost is per-directory **width**, not the number of files in the snapshot. The
same 400,000 files, restic 0.19.1, peak RSS:

| layout | peak RSS |
| ------ | -------- |
| one directory | 537 MB |
| 400 directories of 1000 | 77 MB |

Scaling the width of one directory — flat, zero-byte files, `GOMAXPROCS=2
GOGC=20`:

| entries in one directory | peak RSS |
| ------------------------ | -------- |
| 400,000 | 537 MB |
| 1,000,000 | 1248 MB |
| 1,200,000 | killed under a 1 GiB cap |

`GOMEMLIMIT` moves that cliff by a fraction rather than by an order of
magnitude, which I take as the useful diagnostic: the cost is live data, not
garbage.

## Where it goes

Heap profiles attribute essentially all of it to two places, both in the
archiver:

- `saveDir` submits every entry of a directory and folds the results into the
  directory's tree only once the whole directory has been walked. A finished
  entry is therefore held until then — its `data.Node`, the two paths naming it,
  its `futureNode` channel: about a kilobyte in all.
- The tree blob itself, a few hundred bytes of JSON per entry, is built in
  memory, held for the length of the walk, and then compressed and encrypted
  from that same copy. Verification before upload decompresses it a second time.
  For a million entries that is several hundred megabytes, twice.

## Reproducing it

The harness I used is at
https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro
— a generator with a `-per-dir` knob, and scripts that read peak RSS from
`VmHWM` and that run the same case under a hard cgroup cap, so the answer is a
verdict rather than a number. Its README also records the two ways I first
measured this wrong, in case they save someone else the same day.

## What I would like to do about it

Three changes, which I have written and measured, offered as three separate pull
requests so they can be rejected separately. One directory of a million entries:

1. Fold each finished entry into the tree as the walk goes, holding only a
   bounded window. 1248 MB → 773 MB.
2. Hash a large blob as it decompresses during verification, instead of holding
   the plaintext a second time. 773 MB → 603 MB.
3. Write a wide directory's tree to a temp file as the walk goes, and hash and
   compress it as it is read back, so the plaintext is never in memory in one
   piece. 603 MB → 208 MB, and 1.2M entries then succeeds under a 400 MiB cap.

The third adds a method to an interface, and I would rather hear that it is the
wrong shape before you have had to read it. I am happy to take direction on that
one in particular, or to stop at the first two.

---

# Issue B — for pull request 4

**Title:** `restore` hangs forever, and cannot be killed, on a filesystem whose
`fallocate` never returns

**Body:**

## What happens

`restic restore` onto some sandboxed filesystems — I hit this on managed
WordPress hosting — stops at the first file that needs more than one blob. It
creates the empty files, prints nothing further, and waits. I left one for
several hours.

A goroutine dump (`timeout -s QUIT`) shows every writer parked in `fallocate`,
reached from `ensureSize` → `fs.PreallocateFile`. The filesystem accepts the
syscall and never answers it.

`--sparse` is not a workaround: restic marks a file sparse only when it has one
blob or a zero chunk, so anything over about a megabyte still preallocates.
`restic dump | tar -x` does work, being sequential.

## Why a timeout cannot fix it

I tried that first. Reproduced against a FUSE filesystem that accepts
`fallocate` and never replies:

- The kernel holds the inode lock for the duration, so `pwrite`, `ftruncate` and
  `unlink` on that file all block indefinitely too — and a blocked `unlink` takes
  its whole directory with it.
- The waiting thread sits in `state=D`, `wchan=request_wait_answer`, and ignores
  `SIGKILL`. The process can never exit.
- `FALLOC_FL_KEEP_SIZE` behaves identically.

So issuing the call is an irreversible commitment. A deadline around it only
tells you that you have already lost that file and that process.

## Reproducing it

A FUSE filesystem that answers everything except `fallocate`, which it drops on
the floor, and a restore of any file larger than one blob onto it. I can push
that harness somewhere if it would help.

## What I would like to do about it

Ask the filesystem before relying on it: preallocate a throwaway file whose name
is already unlinked, from a short-lived child process, so a filesystem that never
answers strands that child rather than the restore. Cache the answer per
filesystem. Both existing callers already treat a failed preallocation as
harmless, so where the question goes unanswered the restore simply carries on
without reserving space. Pull request to follow.

---

# Pull request 1

**Branch:** `upstream/pr1-bound-pending-nodes`
**Title:** archiver: Bound the memory a wide directory costs

## What does this PR change? What problem does it solve?

`saveDir` submitted every entry of a directory and folded the results into the
directory's tree only once the whole directory had been walked, so a finished
entry was held — its node, the two paths naming it, and its channel, about a
kilobyte in all — until then. A directory of a million entries therefore needed
roughly a gigabyte on top of the tree itself, which is enough for a host with a
memory cap to kill the backup outright.

The entries of a directory are folded into its tree in the order they appear, so
a finished entry need not be kept. This folds them in as the walk goes, holding
only enough of a window — 10000 entries — to let the entries ahead of a slow one
finish out of order. The file saver's queue is unbuffered, so the walk was
already paced by the file readers, and consuming results earlier costs no
concurrency. Directories no wider than the window behave exactly as before.

Two smaller costs went with it: each entry's name is released once the paths
have been built from it, and the buffer holding the tree is sized from the
directory's entry count rather than being grown and copied repeatedly, which
held two copies of a large tree at once. That second one is worth a warning to
anyone else measuring this — `bytes.Buffer.Grow` made matters worse, not better,
because Go's `growSlice` appends onto a fresh allocation and so holds both sizes
at once: 982 MB became 1565 MB before I stopped using it.

Measured on one flat directory of a million zero-byte files, `GOMAXPROCS=2
GOGC=20`: peak RSS 1248 MB before, 773 MB after. Backing up 600,000 entries in
one directory under a hard 600 MiB cap fails before this change and succeeds
after it.

The tree written is byte for byte unchanged, which I checked the only way that
means anything: same repository, second backup with `--force`, root tree ids
compared, then `check --read-data` and a restore diffed against the source.
(Comparing tree ids across two repositories always shows a difference, because
each gets its own chunker polynomial. That cost me a false alarm.)

`TestArchiverSaveDirWide` covers what the window makes different: a directory
wider than the window, including entries that finish out of order.

The harness behind the numbers, and notes on two ways I first measured this
wrong, is at
https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

Part of #<issue A>.

---

# Pull request 2

**Branch:** `upstream/pr2-verify-large-blob`
**Title:** repository: Verify a large blob without a second copy of it

## What does this PR change? What problem does it solve?

`verifyCiphertext` decrypted and decompressed the blob it had just sealed and
rehashed it, holding the whole plaintext a second time to do so. For a large
tree blob — the tree of a directory with a million entries runs to several
hundred megabytes — that doubled the cost of saving it at exactly the moment the
first copy was still live.

Above 16 MiB uncompressed, this hashes the plaintext as it decompresses instead.
What gets verified does not change; only the copy is gone. Below the threshold
nothing changes, since setting up a streaming decoder is not free and
decompressing the whole blob is the cheaper way round.

The check is the last thing standing between a corrupt buffer and an upload, so a
version of it that always passed would be worse than no check at all.
`TestVerifyCompressedCatchesCorruption` proves the streaming path rejects a wrong
id, a bit flipped at three different offsets, a truncated stream, and input that
was never compressed.

Measured on a backup of one directory of a million entries, peak RSS falls from
773 MB to 603 MB. Disabling verification entirely reaches 592 MB, so almost all
of the difference was the copy.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

Part of #<issue A>.

---

# Pull request 3

**Branch:** `upstream/pr3-spill-wide-tree`
**Title:** archiver: Write a very wide directory's tree through a temp file

## What does this PR change? What problem does it solve?

**This stacks on #\<pr1\> and #\<pr2\>** — its first two commits are those pull
requests, and only the third is new here. I will rebase once they land, and close
this if either is rejected.

A directory's tree is one blob listing every entry, a few hundred bytes each, and
it was built in memory: held while the directory was walked, then compressed and
encrypted from that same copy. For a directory of a million entries that is
several hundred megabytes, and once the pending nodes are bounded it becomes the
largest single cost of the backup — enough that a host which caps process memory
kills the backup outright.

For a directory of 50000 entries or more, this writes the tree to a temp file as
the walk goes and hands the repository the file rather than a buffer.
`saveBlobFromReader` hashes the stream, asks the index whether the repository
already has that blob, and reads the stream a second time to compress it only if
it does not — `saveBlob`'s order, so an unchanged wide directory is recognised
without recompressing its tree. That costs a second pass over a temp file whose
pages the kernel has just written and still holds; getting the order the other
way round cost six times as much on a realistically compressible tree, which the
benchmarks in the diff measure. The compressor declares the plaintext size in the
zstd frame header exactly as `EncodeAll` does, so whoever reads the blob back can
still size its buffer in one go. The plaintext never exists in one piece
anywhere.

The temp file comes from `fs.TempFile`, which returns a file already unlinked, so
closing it is the whole of the cleanup. Creating it is a nicety rather than a
requirement: if it fails, the tree is built in memory as before. Directories
below the threshold are untouched.

The interface addition is the part I would most like reviewed:
`SaveBlobFromReaderAsync` on `restic.BlobSaverAsync`, taking an `io.ReadSeeker`
and a size — seekable because of the two passes. It has exactly one caller. If
you would rather see this shaped differently, or the plaintext size declared some
other way, or the threshold chosen differently, I would much rather hear it now
than after you have merged it.

One flat directory, zero-byte files, `GOMAXPROCS=2 GOGC=20`, peak RSS:

| entries | 0.19.1 | after #\<pr1\> | after #\<pr2\> | with this |
| ------- | ------ | -------------- | -------------- | --------- |
| 400,000 | 537 MB | | | 359 MB |
| 1,000,000 | 1248 MB | 773 MB | 603 MB | 208 MB |
| 1,200,000 | killed | | | 241 MB |

1.2M entries in one directory succeeds under a hard 400 MiB cap. On the real host
that prompted this — 940,000 files, 51.6 GiB — the backup peaks at 325 MB, where
the runs that were killed had reached 540–683 MB.

The tree written is byte for byte unchanged; a restore of it matches the source
exactly; `check --read-data` passes; and a pristine 0.19.1 binary reads what this
one writes, in both directions, writing the same tree for the same input.

`TestTreeSaverSpilledTreeSurvivesCancel` covers the ordering this change makes it
possible to get wrong, which I did get wrong first: a cancelled backup returning
while the repository is still reading the temp file. It reaches the spilling path
by asking for a directory as wide as the threshold rather than by feeding the
builder that many nodes, and it holds the mock repository's read until after the
cancellation, so the ordering is deterministic rather than raced.

This is what rsync does with its file list — stream the metadata rather than
materialise it — adapted to a format that needs each directory's listing
addressed as one blob.

One thing this does not fix, which I would rather say than have found: the read
path is still symmetrical to the old write path. Reading a wide directory's tree
back still materialises the whole blob, so restoring the directory that prompted
this would still want a few hundred megabytes. That is a separate change and I
have not written it.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

Part of #<issue A>.

---

# Pull request 4

**Branch:** `upstream/pr4-preallocation-guard`
**Title:** restore: Don't hang on a filesystem that never preallocates

## What does this PR change? What problem does it solve?

The restorer reserves space for each file before filling it, so that writing its
blobs out of order does not fragment it. Some sandboxed filesystems, seen on
managed WordPress hosting, accept that syscall and never answer it, and the
consequences run deeper than a slow restore: the kernel holds the inode lock
while it waits, so the file can no longer be written, shortened or unlinked —
unlinking it blocks in turn, and takes its directory with it — and the waiting
thread cannot be interrupted, not even by `SIGKILL`, so the process it belongs to
can never exit. A restore stopped at the first file that needed data, left it
empty, and printed nothing.

Making the call is therefore an irreversible commitment, and no deadline around
it can take one back: by the time the deadline passes, that file and that process
are already lost. I built the deadline version first, and that is why this one
exists.

So this asks the filesystem beforehand, with a throwaway file whose name is
unlinked before the call, from a process that exists only to ask — a re-exec of
the restic binary with a hidden `--__preallocate-probe <dir>` argument, handled at
the top of `main` before flags are parsed — so a filesystem that never answers
strands that child process instead of the restore. The answer is kept per
filesystem. Whether the call succeeded is not the question, only whether it came
back at all: one that fails does so promptly, and the caller tolerates a failure
anyway.

Both callers already treat a failed preallocation as harmless and let the writes
extend the file, so where the question goes unanswered, restoring simply carries
on without reserving space.

The part I expect you to dislike is re-execing the binary to ask a question, and
the hidden argument that makes it possible. I could not find a way to ask that
cannot take the asking process with it, which is the whole difficulty; if there
is one, I would much rather use it. `internal/fileio/preallocate_probe_test.go`
covers the probe's own behaviour: a child that never answers
(`TestWaitForProbeGivesUp`), a binary that does not understand the argument
(`TestAskProbeProcessDeclinesANonCooperatingBinary`), a reply without the
expected token (`TestWaitForProbeNeedsTheToken`), a normal process not mistaking
its own arguments for a probe (`TestRunProbeIgnoresANormalProcess`), the probe
leaving nothing behind (`TestProbeDirectoryLeavesNothingBehind`), and a working
filesystem still preallocating (`TestAnswersPreallocationOnAWorkingFilesystem`).

On the host that prompted this, a restore that had run for hours without
finishing a single file now restores a 30,000-file plugin tree in 14 seconds and
a 10 GB tree in 40.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

Closes #<issue B>.
