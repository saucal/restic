# What we are proposing upstream, and in what words

**Nothing is posted.** This file is the working document: the bodies plus the
reasoning behind them, the upstream research, the branch state and the mechanics.

**The text that actually gets posted lives in `saucal/upstream/`** — one file per
artifact, in posting order, body only, nothing to strip out. See
`saucal/upstream/README.md`. Regenerate those files from this one if you edit the
bodies here.

One comment on an existing issue, four draft pull requests, one new issue. All
four branches are built on `restic/restic` master and carry no reference to this
fork, to saucal, to any client, or to how the code was written — acknowledging
that belongs in the pull request's own words, not in a commit trailer. No session
links anywhere.

## What changed from the previous version of this file

Two findings, both from reading upstream rather than guessing:

**There is no issue to open for the memory work. [#2446][] has been open since
2019-10-19, with 29 comments**, labelled `type: feature enhancement` and
`misc: repository format`. Our three changes belong in that thread. The changelog
entries now reference it, and `calens` renders all three as `Enh #2446`.

**The maintainer is part-way through his own fix, and pull request 3 collides with
it.** The trail, in order:

- 2019 — shtratos posts a heap analysis on #2446 naming exactly the three cost
  terms we found: the tree object, its JSON, and its encrypted copy, "the rest is
  mostly Restic bookkeeping and file paths". Our three pull requests are those
  three terms.
- 2019-12 — aawsome builds [#2532][], adding `Node.Subtrees` so a wide directory
  splits across several tree blobs. 1 GB → 60 MB. Closed unmerged; it changed the
  repository format.
- 2022-07 — MichaelEischer merges [#3773][], "Reduce memory usage for large
  directories/files", 30–50% by shrinking `FutureNode`. He writes that it "is not
  intended as a complete solution, as that would require a repository format
  change as discussed in #2532".
- 2026-01-31 — he merges [#5613][], replacing `data.Tree` with an iterator,
  "in order to eventually be able to chunk trees (#2446)", and says on #2446 that
  it "will take at least two or three further large PRs".
- 2026-07-10 — he opens [#21943][] **as his own draft**, still open: an
  `object.Reader`/`object.Writer` for blob sequences, "required to use a sequence
  of blobs as JSON source/target".

That last one is the general form of what our pull request 3 does specially. His
endgame is chunked tree blobs; ours is a temp file. Chunked trees also fix the
`Fatal: blob is larger than 4GB` that #2446 reporters hit at 5M entries in one
directory, which our approach does not.

So the plan is no longer "propose three changes". It is: put the measurements into
#2446, offer the two changes that stand on their own regardless of his roadmap,
offer the third as an explicit stopgap he is free to refuse, and offer to work on
his design instead.

[#2446]: https://github.com/restic/restic/issues/2446
[#2532]: https://github.com/restic/restic/pull/2532
[#3773]: https://github.com/restic/restic/pull/3773
[#5613]: https://github.com/restic/restic/pull/5613
[#21943]: https://github.com/restic/restic/pull/21943

## Which pull request contains which — read this first

Three of the four are self-contained. One is not.

```
restic/restic master
  |
  +-- PR 1  archiver: Bound the memory a wide directory costs
  |         SELF-CONTAINED. 1 commit. Merges on its own, in any order.
  |
  +-- PR 2  repository: Verify a large blob without a second copy of it
  |         SELF-CONTAINED. 1 commit. Merges on its own, in any order.
  |         Independent of PR 1 -- neither contains the other.
  |
  +-- PR 3  archiver: Write a very wide directory's tree through a temp file
  |         NOT self-contained. 3 commits:
  |             1. PR 1's commit        <- duplicate
  |             2. PR 2's commit        <- duplicate
  |             3. the spill commit     <- the only new work, 10 files, 568+/38-
  |         Needs PR 1 and PR 2 merged first; a rebase then drops the
  |         duplicates and leaves one commit.
  |
  +-- PR 4  restore: Don't hang on a filesystem that never preallocates
            SELF-CONTAINED. 1 commit. Unrelated to the other three --
            different subsystem, different issue, no shared files.
```

| | commits | self-contained | contains | merge order |
| - | ------- | -------------- | -------- | ----------- |
| PR 1 | 1 | yes | — | any time |
| PR 2 | 1 | yes | — | any time |
| PR 3 | 3 | **no** | PR 1 + PR 2 | after both, then rebase |
| PR 4 | 1 | yes | — | any time |

Verified by patch-id, not by reading: PR 1's and PR 2's changes are present in
PR 3 byte for byte.

**Why PR 3 cannot simply be based on PR 1.** A pull request from a fork must be
based on a branch in `restic/restic`, so there is no way to make GitHub show only
the third commit. Until PR 1 and PR 2 merge, anyone opening PR 3 sees 13 files and
871+/83- — which is why its body says so in the first paragraph, and why the diff
of just the new commit is kept separately for our own review.

**If they ask for it all in one pull request instead**, PR 3 already *is* that
pull request. Nothing needs rebuilding: mark it ready, close PR 1 and PR 2 as
superseded, and two pull requests merge in total — PR 3 and PR 4.

## Posting sequence

| step | what | why in this order |
| ---- | ---- | ----------------- |
| 1 | Comment on #2446 | The decision lives there, not in the review queue |
| 2 | Draft PR 3 (spill) | Opened first only so 1 and 2 have a number to point at |
| 3 | Draft PR 1 (bound pending nodes) | References #2446 and PR 3 |
| 4 | Draft PR 2 (verify large blob) | References #2446 and PR 3 |
| 5 | Edit PR 3's body | Add PR 1 and PR 2's numbers, now known |
| 6 | Open Issue B, then Draft PR 4 | Independent of all of the above |

Each is a **draft** pull request. Two things follow from that, both deliberate:

- **A draft is not in the review queue.** That is the point while #2446 is
  unanswered — but it also means nothing happens until they are marked ready.
  Mark PR 1 and PR 2 ready as soon as the #2446 conversation points a direction,
  or they will simply sit.
- **CI still runs.** `tests.yml` triggers on `pull_request` with no draft filter,
  so the full matrix fires on every push. That is useful signal for us and a real
  cost in their Actions minutes, so push finished branches, not work in progress.

Cross-repo constraint: a PR from `saucal/restic` must be based on a branch in
`restic/restic`, so **pull request 3 cannot be stacked**. Its diff carries PR 1
and PR 2's commits — 3 commits, 951 lines — until those merge, at which point a
rebase shrinks it to one commit. That is stated plainly in its body.

## State of the four branches, as of 2026-09-28

All four rebased onto `restic/restic` master at `5127c4abf`. On that base, each
branch: builds, is `gofmt` clean over the files it touches, passes
`golangci-lint run --new-from-rev=upstream/master` with 0 issues, passes the test
suite, and passes `calens`. A full `go test ./...` on pull request 3 fails exactly
the six tests that also fail on unmodified master in this environment
(`TestMount`, `TestMountSameTimestamps`, `TestStdinFromCommand`,
`TestStdinFromCommandNoOutput`, `TestNodeRestoreAt`, `TestOverwriteXattr` — no
OSXFUSE, macOS xattr behaviour) and nothing else.

`gofmt` also flags `internal/backend/s3/s3_test.go`, on pristine master as much as
on our branches: upstream reformatted it with go 1.27's `gofmt` and the local
toolchain is 1.26. Not a file any of these branches touches.

Pull request 3's code is byte for byte the code that went through the full CI
matrix and has been running in production since; the only differences are files
upstream itself changed and we do not touch. The patch still fits post-#5613
master: `TreeJSONBuilder` survived it, `TreeWriter` wraps it, and
`BlobSaverAsync` — the interface pull request 3 extends — is from his own #5612.

**Rebase again before posting** and re-run those checks. Upstream committed twice
during the few days this was being prepared.

## Changelog mechanics

Three files, all keyed to #2446 by their first URL, which is what `calens` groups
on — the filenames only have to differ:

| branch | file | rename before posting |
| ------ | ---- | --------------------- |
| PR 1 | `changelog/unreleased/issue-2446` | keep as is |
| PR 2 | `changelog/unreleased/pull-99996` | → `pull-<PR 2's number>` |
| PR 3 | `changelog/unreleased/pull-99995` | → `pull-<PR 3's number>` |
| PR 4 | `changelog/unreleased/pull-99999` | → `issue-<Issue B's number>` |

Fix the placeholder URL on the last line of each to match, then amend. Offer in
each body to consolidate into a single `issue-2446` entry if they would rather.

## The note that ends every pull request body

Verbatim, at the end of the first section. It is the whole of the disclosure: no
footnotes, no attribution trailers, no links to anything but restic and the
harness.

> **How this was written.** I am not a Go developer, though I am an engineer. I
> came at this from operationally using restic to back up WordPress sites, which
> sometimes hold very large numbers of small thumbnail files in a single
> directory. I had an AI assistant take a stab at the problem, and what it
> produced solved my use case — but I am not claiming it is the right solution to
> the problem, and I know there is a whole universe of use cases I cannot think of
> or cover, especially without Go-specific knowledge. What I can vouch for is the
> measuring: the numbers above are ones I took myself, before and after, and the
> change passes the existing test suite along with the tests added here and has
> been running on real backups. I can follow directions, so if the shape is wrong,
> tell me what it should be and I will do the work.

---

# Step 1 — comment on issue #2446

This is the important one. Everything else is optional from their side.

**Body:**

Seven years on, this is still costing people real backups, so here are fresh
measurements and an offer.

## Measurements on 0.19.1

The cost is per-directory **width**, not the number of files in the snapshot. The
same 400,000 files:

| layout | peak RSS |
| ------ | -------- |
| one directory | 537 MB |
| 400 directories of 1000 | 77 MB |

Scaling one directory — flat, zero-byte files, `GOMAXPROCS=2 GOGC=20`:

| entries in one directory | peak RSS |
| ------------------------ | -------- |
| 400,000 | 537 MB |
| 1,000,000 | 1248 MB |
| 1,200,000 | killed under a 1 GiB cap |

`GOMEMLIMIT` moves that cliff by a fraction rather than an order of magnitude,
which is the useful diagnostic: the cost is live data, not garbage.

What sent me here is a WordPress uploads directory of about 1.14M files on managed
hosting that kills a process at roughly 680 MB. The snapshot is only 51 GiB and
barely changes, but it had not completed a backup for months.

On the question asked a few times in this thread — whether anyone really has that
many files *directly* in one directory, and whether they should be reorganising
instead — WordPress reaches these widths on its own, without anyone mismanaging
anything. Every upload is written to a flat `wp-content/uploads/YYYY/MM/`
directory, and WordPress then generates a set of scaled thumbnails for it beside
the original: the core sizes, plus whatever the active theme and plugins register.
A site uploading a few thousand images a month accumulates tens of thousands of
files in that one month directory, and the directory is addressed by URL, so it
cannot be restructured without breaking every link to it. Nobody chose this
layout, and the site owner cannot change it. That is why I do not think this only
affects unusual setups — it is the default shape of the most widely deployed CMS
on the web, and it gets worse every month a site stays up.

Heap profiles reproduce @shtratos's 2019 breakdown almost exactly — the tree
object, its JSON, its encrypted copy, plus bookkeeping and paths — with one term
he did not separate out: `saveDir` holds every *finished* entry, its `data.Node`,
the two paths naming it and its `futureNode` channel, about a kilobyte each, until
the whole directory has been walked. #3773 shrank those structs; it did not
shorten how long the array lives.

The harness is at
https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro
— a generator with a `-per-dir` knob, and scripts that read peak RSS from `VmHWM`
and re-run each case under a hard cgroup cap so the answer is a verdict rather
than a number. Its README also records two ways I first measured this wrong, in
case they save someone else a day.

## Three changes, measured, in draft pull requests

One directory of a million entries:

| | peak RSS |
| --- | --- |
| 0.19.1 | 1248 MB |
| fold each finished entry into the tree as the walk goes (#\<pr1\>) | 773 MB |
| hash a large blob as it decompresses when verifying it (#\<pr2\>) | 603 MB |
| write a wide directory's tree through a temp file (#\<pr3\>) | 208 MB |

1.2M entries in one directory then succeeds under a hard 400 MiB cap. On the real
host, 940,000 files and 51.6 GiB now peaks at 325 MB against the 540–683 MB that
was being killed. The tree written is byte for byte unchanged throughout, a
restore matches the source exactly, `check --read-data` passes, and a pristine
0.19.1 binary reads what these builds write in both directions.

The first two are local and need no format change; I think they stand on their own
whatever happens to the rest. **The third I expect you to refuse, and I would
rather say why myself.** It adds `SaveBlobFromReaderAsync` to `BlobSaverAsync` and
spills the tree to a temp file, which is the special case of what #21943's
`object.Writer` does generally. It is a stopgap for people stuck today, it is new
interface surface you would carry and then remove, and it does not fix the
`blob is larger than 4GB` ceiling that chunked trees will. If chunking is close,
say so and I will close it.

## The offer

I would much rather help finish your design than carry a patched fork. Having read
#5613 and #21943, the direction is clear and I am not proposing an alternative to
it. If any of the work between here and chunked tree blobs parallelises — porting
call sites, the reader side, `Dumper.writeNode`, tests, measurement on directories
this wide — I have capacity to take pieces on under your direction, with the design
staying entirely yours.

Being straight about what you would be accepting. I am an engineer but not a Go
developer, I came at this from operating restic rather than from writing it, and I
work with heavy AI assistance. Tell me what would actually help and what would
just be noise, and I will work to that.

---

# Step 2 — draft pull request 3

**Branch:** `upstream/pr3-spill-wide-tree`
**Title:** archiver: Write a very wide directory's tree through a temp file
**Open as: draft**

## What does this PR change? What problem does it solve?

**Read #2446 first — this is the change I expect you to refuse, and it is opened
as a draft for that reason.** It is here so the other two have something concrete
to point at, and so anyone hitting this today has a build that works.

**Three commits, and not self-contained: it carries #\<pr1\>'s and #\<pr2\>'s
commits as well as its own.** A pull request from a fork has to be based on a
branch in this repository, so there is no way to stack it and show you only the
third commit, which is the only new work here. Once those two land, a rebase drops
the duplicates and leaves one commit.

A directory's tree is one blob listing every entry, a few hundred bytes each, and
it was built in memory: held while the directory was walked, then compressed and
encrypted from that same copy. For a directory of a million entries that is
several hundred megabytes, and once the pending nodes are bounded it becomes the
largest single cost of the backup.

For a directory of 50000 entries or more, this writes the tree to a temp file as
the walk goes and hands the repository the file rather than a buffer.
`saveBlobFromReader` hashes the stream, asks the index whether the repository
already has that blob, and reads the stream a second time to compress it only if
it does not — `saveBlob`'s order, so an unchanged wide directory is recognised
without recompressing its tree. That costs a second pass over a temp file whose
pages the kernel has just written and still holds; getting the order the other way
round cost six times as much on a realistically compressible tree, which the
benchmarks in the diff measure. The compressor declares the plaintext size in the
zstd frame header exactly as `EncodeAll` does, so whoever reads the blob back can
still size its buffer in one go. The plaintext never exists in one piece anywhere.

The temp file comes from `fs.TempFile`, which returns a file already unlinked, so
closing it is the whole of the cleanup. Creating it is a nicety rather than a
requirement: if it fails, the tree is built in memory as before. Directories below
the threshold are untouched.

### How this sits next to #21943

`SaveBlobFromReaderAsync` on `restic.BlobSaverAsync` — an `io.ReadSeeker` and a
size, seekable because of the two passes, one caller — is the special case of what
your `object.Writer` does generally, and chunked tree blobs make it unnecessary.
It also does not fix the `blob is larger than 4GB` failure reported on #2446 at
5M entries, which chunking does.

So I am not asking you to take this on its merits as a design. I am asking
whether a stopgap is worth having while the real fix lands, given that a
memory-capped host cannot back up such a directory at all today. If the answer is
no, close it — the measurements in #2446 are the part I actually care about, and
#\<pr1\> and #\<pr2\> do not depend on this.

One flat directory, zero-byte files, `GOMAXPROCS=2 GOGC=20`, peak RSS:

| entries | 0.19.1 | after #\<pr1\> | after #\<pr2\> | with this |
| ------- | ------ | -------------- | -------------- | --------- |
| 400,000 | 537 MB | | | 359 MB |
| 1,000,000 | 1248 MB | 773 MB | 603 MB | 208 MB |
| 1,200,000 | killed | | | 241 MB |

1.2M entries in one directory succeeds under a hard 400 MiB cap. On the real host
— 940,000 files, 51.6 GiB — the backup peaks at 325 MB where the runs being killed
had reached 540–683 MB.

The tree written is byte for byte unchanged; a restore of it matches the source
exactly; `check --read-data` passes; and a pristine 0.19.1 binary reads what this
one writes, in both directions, writing the same tree for the same input.

`TestTreeSaverSpilledTreeSurvivesCancel` covers the ordering this makes it
possible to get wrong, which I did get wrong first: a cancelled backup returning
while the repository is still reading the temp file. It reaches the spilling path
by asking for a directory as wide as the threshold rather than by feeding the
builder that many nodes, and holds the mock repository's read until after the
cancellation, so the ordering is deterministic rather than raced.

One thing this does not fix, which I would rather say than have found: the read
path is still symmetrical to the old write path. Reading a wide directory's tree
back still materialises the whole blob, so restoring the directory that prompted
this would still want a few hundred megabytes.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

#2446, where the measurements and the question about #21943 are.

---

# Step 3 — draft pull request 1

**Branch:** `upstream/pr1-bound-pending-nodes`
**Title:** archiver: Bound the memory a wide directory costs
**Open as: draft**

## What does this PR change? What problem does it solve?

One of three changes measured on #2446. **One commit, self-contained:** it does
not depend on #\<pr2\> or #\<pr3\> and can be merged on its own, in any order. It
needs no format change and adds no interface, and it picks up where #3773
stopped.

`saveDir` submitted every entry of a directory and folded the results into the
directory's tree only once the whole directory had been walked, so a finished entry
was held — its node, the two paths naming it, and its channel, about a kilobyte in
all — until then. #3773 shrank those structs; what it did not change is how long
the array lives. A directory of a million entries therefore still needed roughly a
gigabyte on top of the tree itself, which is enough for a host with a memory cap
to kill the backup outright.

The entries of a directory are folded into its tree in the order they appear, so a
finished entry need not be kept. This folds them in as the walk goes, holding only
enough of a window — 10000 entries — to let the entries ahead of a slow one finish
out of order. The file saver's queue is unbuffered, so the walk was already paced
by the file readers, and consuming results earlier costs no concurrency.
Directories no wider than the window behave exactly as before.

Two smaller costs went with it: each entry's name is released once the paths have
been built from it, and the buffer holding the tree is sized from the directory's
entry count rather than being grown and copied repeatedly, which held two copies
of a large tree at once. That second one is worth a warning to anyone else
measuring this — `bytes.Buffer.Grow` made matters worse, not better, because Go's
`growSlice` appends onto a fresh allocation and so holds both sizes at once:
982 MB became 1565 MB before I stopped using it.

Measured on one flat directory of a million zero-byte files, `GOMAXPROCS=2
GOGC=20`: peak RSS 1248 MB before, 773 MB after. Backing up 600,000 entries in one
directory under a hard 600 MiB cap fails before this change and succeeds after it.

The tree written is byte for byte unchanged, which I checked the only way that
means anything: same repository, second backup with `--force`, root tree ids
compared, then `check --read-data` and a restore diffed against the source.
Comparing tree ids across two repositories always shows a difference, because each
gets its own chunker polynomial — that cost me a false alarm.

`TestArchiverSaveDirWide` covers what the window makes different: a directory
wider than the window, including entries that finish out of order.

The harness behind the numbers, and notes on two ways I first measured this wrong:
https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro

Happy to fold this changelog entry together with the other two into one
`issue-2446` entry if you would rather have a single line for all of it.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

#2446. See also #\<pr3\>, the third change, which I expect to close.

---

# Step 4 — draft pull request 2

**Branch:** `upstream/pr2-verify-large-blob`
**Title:** repository: Verify a large blob without a second copy of it
**Open as: draft**

## What does this PR change? What problem does it solve?

One of three changes measured on #2446. **One commit, self-contained:** it does
not depend on #\<pr1\> or #\<pr3\> and can be merged on its own, in any order.

This is the "encrypted variant" term @shtratos identified on #2446 in 2019 and
#3773 named but did not address. It is independent of #21943 too — it helps any
large blob, not only a wide directory's tree.

`verifyCiphertext` decrypted and decompressed the blob it had just sealed and
rehashed it, holding the whole plaintext a second time to do so. For a large tree
blob — the tree of a directory with a million entries runs to several hundred
megabytes — that doubled the cost of saving it at exactly the moment the first copy
was still live.

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
773 MB to 603 MB. Disabling verification entirely reaches 592 MB, so almost all of
the difference was the copy.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

#2446.

---

# Step 6a — new issue for the preallocation hang

Nothing upstream covers this. The neighbours are #5543 (Rook-Ceph restore
corruption), #5553 (closed, serialize writes when preallocation is impossible),
#5045 (merged, retry preallocate when interrupted by a signal) and #2675/#2893
(where preallocation was introduced) — all about preallocation failing or racing,
none about it never returning.

**Title:** `restore` hangs forever, and cannot be killed, on a filesystem whose
`fallocate` never returns

**Body:**

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

---

# Step 6b — draft pull request 4

**Branch:** `upstream/pr4-preallocation-guard`
**Title:** restore: Don't hang on a filesystem that never preallocates
**Open as: draft**

## What does this PR change? What problem does it solve?

**One commit, self-contained**, and unrelated to the memory work on #2446 —
different subsystem, no shared files.

The restorer reserves space for each file before filling it, so that writing its
blobs out of order does not fragment it. Some sandboxed filesystems, seen on
managed WordPress hosting, accept that syscall and never answer it, and the
consequences run deeper than a slow restore: the kernel holds the inode lock while
it waits, so the file can no longer be written, shortened or unlinked — unlinking
it blocks in turn, and takes its directory with it — and the waiting thread cannot
be interrupted, not even by `SIGKILL`, so the process it belongs to can never
exit. A restore stopped at the first file that needed data, left it empty, and
printed nothing.

Making the call is therefore an irreversible commitment, and no deadline around it
can take one back: by the time the deadline passes, that file and that process are
already lost. I built the deadline version first, and that is why this one exists.

So this asks the filesystem beforehand, with a throwaway file whose name is
unlinked before the call, from a process that exists only to ask — a re-exec of
the restic binary with a hidden `--__preallocate-probe <dir>` argument, handled at
the top of `main` before flags are parsed — so a filesystem that never answers
strands that child process instead of the restore. The answer is kept per
filesystem. Whether the call succeeded is not the question, only whether it came
back at all: one that fails does so promptly, and the caller tolerates a failure
anyway.

Both callers already treat a failed preallocation as harmless and let the writes
extend the file, so where the question goes unanswered, restoring simply carries on
without reserving space.

The part I expect you to dislike is re-execing the binary to ask a question, and
the hidden argument that makes it possible. I could not find a way to ask that
cannot take the asking process with it, which is the whole difficulty; if there is
one, I would much rather use it. `internal/fileio/preallocate_probe_test.go` covers
the probe's own behaviour: a child that never answers (`TestWaitForProbeGivesUp`),
a binary that does not understand the argument
(`TestAskProbeProcessDeclinesANonCooperatingBinary`), a reply without the expected
token (`TestWaitForProbeNeedsTheToken`), a normal process not mistaking its own
arguments for a probe (`TestRunProbeIgnoresANormalProcess`), the probe leaving
nothing behind (`TestProbeDirectoryLeavesNothingBehind`), and a working filesystem
still preallocating (`TestAnswersPreallocationOnAWorkingFilesystem`).

On the host that prompted this, a restore that had run for hours without finishing
a single file now restores a 30,000-file plugin tree in 14 seconds and a 10 GB tree
in 40.

> **How this was written.** [the note, verbatim]

## Was the change previously discussed in an issue or on the forum?

Closes #\<issue B\>.
