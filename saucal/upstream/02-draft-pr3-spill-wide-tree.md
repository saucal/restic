<!-- POST AS: a DRAFT pull request
     TITLE:  archiver: Write a very wide directory's tree through a temp file
     BRANCH: upstream/pr3-spill-wide-tree  ->  restic/restic:master  (3 commits, CARRIES PR1+PR2) -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

## What does this PR change? What problem does it solve?

**Read #2446 first — this is the change I expect you to refuse, and it is opened
as a draft for that reason.** It is here so the other two have something concrete
to point at, and so anyone hitting this today has a build that works.

**Three commits, and not self-contained: it carries #<pr1>'s and #<pr2>'s
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
#<pr1> and #<pr2> do not depend on this.

One flat directory, zero-byte files, `GOMAXPROCS=2 GOGC=20`, peak RSS:

| entries | 0.19.1 | after #<pr1> | after #<pr2> | with this |
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

## Was the change previously discussed in an issue or on the forum?

#2446, where the measurements and the question about #21943 are.
