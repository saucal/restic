# Things worth building in this fork

Collected while fixing the Pressable restore hang (2026-09-16/17). None of it is
started. Each entry says what the gap was, because a year from now the reason
matters more than the idea.

## A stall watchdog

**Why:** the preallocation hang cost days. restic printed nothing, exited never,
and the only way in was a `SIGQUIT` goroutine dump on the host. A watchdog that
noticed "no file completed for N minutes; 8 workers are blocked in `pwrite`"
would have named the problem in minutes.

**Shape:** the restorer and backup already track progress for the status line.
Watch that counter; when it does not move for a while, print what the workers are
doing (their stacks, summarised) rather than staying silent. General enough that
upstream would plausibly take it.

## Ordered writes within a file

**Why:** restic writes a file's blobs out of order from parallel workers, so
writes land past the end of the file and the filesystem fills the gap. On
filesystems that must materialise those zeros, that is where upstream's open
corruption reports live (#5543 CephFS, #5480 exFAT), and it is also the only
reason preallocation is needed at all — rsync, which writes each file
sequentially, defaults `preallocate_files = 0` and never has the problem.

**Shape:** `--restore-order=sequential`: buffer out-of-order blobs up to a cap and
write ascending, falling back to today's behaviour past the cap. The cost is
memory or re-read — which is exactly the trade upstream made in PR 2195 when they
chose to download each pack once. Even as an option it would let anyone **test**
the corruption hypothesis, which two failed upstream fixes (#5553, #5627) never
could.

## Restore concurrency control

**Why:** while investigating the corruption question there was no way to vary
restore parallelism directly — it follows the backend connection count, so
`-o rest.connections=1` is the closest thing and it changes downloading too.

**Shape:** an explicit worker count for the restorer, so write concurrency can be
isolated from transfer concurrency.

## A manifest of what was restored

**Why:** `restore --verify` is a real integrity check (size, then every blob
hash), but it costs a second full read of the restored tree. Our action wants to
know "did this land correctly" on hosts with unusual storage, ideally without
paying that twice.

**Shape:** have `restore` emit path + hash as it writes, `--json` friendly, so the
caller can check against its own copy without re-reading.

## Itemized changes for restore, like rsync's

**Why:** restic says *that* an item changed, never *what* about it changed. The
restorer classifies each one as `file restored`, `file updated`, `file unchanged`,
`deleted` (`internal/ui/restore/progress.go`), and `--json` flattens that further
to restored/updated/unchanged/deleted. So a staging recreation can report that it
touched 4,000 files without being able to say whether that was content, mtime,
permissions or ownership — which is exactly the question asked when a restore
changes more than expected, and the question `--overwrite if-changed` silently
answers on its own.

rsync answers it in eleven positions, `YXcstpoguax` (`log.c`): update type and
file type, then one column each for checksum, size, time, permissions, owner,
group, access time, ACL and xattr — `.` when that attribute matches, its letter
when it differs, `+` for a new item. Reading `>f.st......` tells you the content
and mtime differ and nothing else does.

**Shape:** the restorer already compares size and mtime to decide `if-changed`,
and knows a file's blob hashes, so most columns are available where the decision
is made rather than needing new work. Emit them per item under an explicit flag,
and extend the JSON item messages with the same fields so tooling can aggregate
without parsing text. Pairs naturally with `--dry-run`: "here is what this
restore would change, and why" is a far better pre-flight than a count.

**Careful about:** restic does not stat every attribute rsync does, and some
(ACLs, xattrs) it restores without comparing first. Columns it cannot honestly
fill should read as unknown rather than as "matches" — an itemization that lies
by omission is worse than none.

## A memory ceiling for backup — mostly answered, one piece left

**What happened:** the diagnostics did their job. They said the memory went to
directory *width*, not index size, and `v0.19.1-saucal.3` fixed that: one flat
directory of a million entries went from 1248 MB to 208 MB, and elka backs up on
Pressable at a measured peak of 272 MB heap / 325 MB total against the 540-683 MB
that used to kill it. So a `--memory-limit` that throttles concurrency is no longer
the interesting idea it was.

**What is left:** `GOMEMLIMIT` is worth setting on the fleet and still is not set.
The buffers that compress and seal a blob are garbage, and without a limit Go grows
the heap rather than collecting them; it bought 600k -> 800k entries per directory
in the Docker measurements. It costs one environment variable beside the existing
`GOGC=20` and covers the next surprise rather than this one.

## Reading a very wide directory's tree

**Why:** the write path no longer holds a whole tree in memory, but the read path
still does. A directory of a million entries has a ~300 MB tree blob, and
`LoadBlob` returns it whole, so `restore`, `check`, `ls` and `find` on such a
snapshot each need that much — the asymmetry is now the larger half of the problem
for elka, whose backup succeeds in 325 MB but whose restore would not.

**Shape:** a streaming blob load, feeding `data.NewTreeNodeIterator` from a reader
rather than from a `[]byte`. The iterator already exists and already streams; it is
the layer below it that materialises. Decrypting needs the whole ciphertext, but
decompression and JSON parsing can both be incremental, so the ceiling would fall
to roughly the compressed size.

**Worth knowing first:** nobody has tried restoring elka. That measurement should
come before the work — `restore --dry-run` will not do, it does not load data, but
`ls latest --recursive` on that snapshot would show the shape of it.

## A more compact directory listing

**Why:** after the wide-directory work, the one term that still scales with
directory width is the entry names: 134 MB of the 241 MB measured at 1.2M entries.
They are held because the tree has to be written in sorted order, and each is its
own Go string with its own allocation and size-class rounding.

**Shape:** rsync's approach — one slab of bytes plus offsets, sorted as offsets,
which is roughly 89 bytes per entry against the current ~112. About a 20% cut on
that term, so ~25 MB at a million entries.

**Why it is not done:** the measured headroom made it unnecessary, and it trades
clear code for a modest saving. Worth doing only if a site turns up that needs it —
the fleet's peak figures will say, now that every backup reports one.

## Deferred decisions, not features

* Nothing has been posted upstream yet. `saucal/UPSTREAM-PRS.md` holds the whole
  submission word for word: a comment on upstream #2446, four draft pull requests
  (`upstream/pr1-bound-pending-nodes`, `upstream/pr2-verify-large-blob`,
  `upstream/pr3-spill-wide-tree`, `upstream/pr4-preallocation-guard`) and one new
  issue for the preallocation hang. All four are rebased on current upstream master,
  build clean, lint clean, pass the suite and pass `calens`.
* **The memory problem is upstream #2446, open since 2019, and the maintainer is
  part-way through his own fix.** #3773 (2022) shrank the structs; #5613 (merged
  2026-01-31) replaced `data.Tree` with an iterator "in order to eventually be able
  to chunk trees (#2446)"; #21943 is his open draft adding `object.Reader`/`Writer`
  for blob sequences, "required to use a sequence of blobs as JSON source/target".
  Chunked tree blobs are the endgame, and they also fix the `blob is larger than 4GB`
  failure at 5M entries that our spill does not.

  **What that means for us:** our first two changes are local and stand on their own;
  the third (`SaveBlobFromReaderAsync` plus the temp file) is the special case of his
  `object.Writer` and should be offered as a stopgap he is free to refuse. We have
  offered engineering capacity on his design instead of carrying the fork — that offer
  is in the #2446 comment draft, and if taken up it becomes the real work here.
* The minio CI fix is dead. Upstream hit the same dead download — `dl.minio.io` now
  answers 410 Gone — and fixed it differently in #22067, merged 2026-09-20, replacing
  minio with seaweedfs. `upstream/ci-install-minio-from-source` can be deleted.
* The diagnostics branch (`upstream/resource-diagnostics`) is not going upstream as it
  stands. It is our own instrumentation, a `--diag` surface nobody asked for, and the
  branch has 40 MB of built binaries committed to `dist/` by accident.
