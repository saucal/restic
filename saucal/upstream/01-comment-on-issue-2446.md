<!-- POST AS: a comment on the existing issue
     TARGET: https://github.com/restic/restic/issues/2446
     BRANCH: none -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

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
| fold each finished entry into the tree as the walk goes (#<pr1>) | 773 MB |
| hash a large blob as it decompresses when verifying it (#<pr2>) | 603 MB |
| write a wide directory's tree through a temp file (#<pr3>) | 208 MB |

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
