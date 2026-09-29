<!-- POST AS: a comment on the existing issue
     TARGET: https://github.com/restic/restic/issues/2446
     BRANCH: none -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

Measurements on 0.19.1, the shape of directory that produces them, and an offer
of help at the end.

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

The thread has asked a few times whether anyone really has that many files
*directly* in one directory. In WordPress this is the default layout rather than a
choice. Every upload goes into a flat `wp-content/uploads/YYYY/MM/` directory, and
WordPress generates a set of scaled thumbnails beside the original: the core
sizes, plus whatever the active theme and plugins register. A site uploading a few
thousand images a month accumulates tens of thousands of files in that one
directory, and the count only grows. The directory is addressed by URL, so it
cannot be restructured without breaking existing links.

Heap profiles reproduce @shtratos's 2019 breakdown almost exactly — the tree
object, its JSON, its encrypted copy, plus bookkeeping and paths — with one term
he did not separate out: `saveDir` holds every *finished* entry, its `data.Node`,
the two paths naming it and its `futureNode` channel, about a kilobyte each, until
the whole directory has been walked. #3773 shrank those structs; it did not
shorten how long the array lives.

The harness is at
https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro
— a generator with a `-per-dir` knob, and scripts that read peak RSS from `VmHWM`
and re-run each case under a hard cgroup cap. Its README notes two ways I measured
this wrong at first, both of which changed the numbers materially.

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

The first two are local and need no format change. The third adds
`SaveBlobFromReaderAsync` to `BlobSaverAsync` and spills the tree to a temp file,
which is the special case of what #21943's `object.Writer` does generally. Three
things count against it: it is interface surface you would carry and then remove,
it does not fix the `blob is larger than 4GB` failure that chunked trees will, and
it only helps the write path. It is useful today on hosts that cannot complete a
backup at all. If chunked trees are close, say so and I will close it.

## The offer

I would rather help with the chunked-tree work than maintain a fork. From #5613 and
#21943 the direction looks clear, and I am not proposing an alternative to it. If
any of the work between here and chunked tree blobs can be parallelised — porting
call sites, the reader side, `Dumper.writeNode`, tests, measurement on directories
this wide — I have capacity to take pieces on, with the design decisions yours.

Being straight about what you would be accepting. I am an engineer but not a Go
developer, I came at this from operating restic rather than from writing it, and I
work with heavy AI assistance. Tell me what would actually help and what would
just be noise, and I will work to that.
