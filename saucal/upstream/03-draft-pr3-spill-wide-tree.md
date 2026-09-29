<!-- DRAFT PULL REQUEST. Branch upstream/pr3-spill-wide-tree -> restic/restic:master (3 commits: carries PR1 + PR2)
     Title: archiver: Write a very wide directory's tree through a temp file -->

## What does this PR change? What problem does it solve?

Part of #2446. **Three commits, not self-contained:** #<pr1>, #<pr2>, and the change below. A fork's PR can't be stacked, so this carries both. To review everything together, use this one and close the other two; if they merge separately, a rebase leaves one commit here.

It's a draft because it overlaps #21943. Whether restic wants it is your call.

A directory's tree blob is built in memory, held for the whole walk, then compressed and encrypted from that copy: hundreds of MB for 1M entries.

For directories of 50000 entries or more, this writes the tree to a temp file (`fs.TempFile`, already unlinked) during the walk and passes the file to a new `SaveBlobFromReaderAsync` on `restic.BlobSaverAsync`. The repository hashes the file, checks the index, and compresses in a second pass only if the blob is new, the same order as `saveBlob`, so an unchanged directory isn't recompressed. The zstd frame declares the content size, as `EncodeAll` does. If the temp file can't be created, it falls back to the in-memory path.

Compared with #21943: this is a special case of `object.Writer`, adds an interface method that chunked trees would make unnecessary, doesn't fix the `blob is larger than 4GB` limit, and doesn't change the read path (reading such a tree still loads it whole). It does let memory-capped hosts back up these directories now.

One flat directory, `GOMAXPROCS=2 GOGC=20`, peak RSS:

| entries | 0.19.1 | + #<pr1> | + #<pr2> | + this |
|---|---|---|---|---|
| 1,000,000 | 1248 MB | 773 MB | 603 MB | 208 MB |
| 1,200,000 | killed | | | 241 MB |

1.2M entries completes under a 400 MiB cap. On a production host (940k files, 51.6 GiB) the peak is 325 MB; it was previously killed at 540-683 MB. The tree is unchanged, `check --read-data` passes, restores match, and 0.19.1 reads what this writes and vice versa.

`TestTreeSaverSpilledTreeSurvivesCancel` covers a cancellation while the repository is still reading the temp file.

> **How this was written:** I'm an engineer, not a Go developer. I use restic to back up WordPress sites, which can hold very large numbers of thumbnails in one directory. An AI assistant wrote this code; it solves my case, but I don't claim it's the right solution, and there are use cases I can't anticipate without Go experience. The numbers are my own measurements; the change passes the existing test suite plus the tests added here, and has run on real backups. Happy to rework it in whatever direction you prefer.

## Was the change previously discussed in an issue or on the forum?

#2446

## Checklist

- [x] I have added tests for all code changes
- [ ] I have added documentation for relevant changes (in the manual)
- [x] There's a new file in `changelog/unreleased/`
- [ ] I'm done! This pull request is ready for review.
