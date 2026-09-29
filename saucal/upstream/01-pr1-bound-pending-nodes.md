<!-- PULL REQUEST, ready for review. Branch upstream/pr1-bound-pending-nodes -> restic/restic:master
     Title: archiver: Bound the memory a wide directory costs -->

## What does this PR change? What problem does it solve?

Part of #2446. One commit, self-contained.

`saveDir` keeps every finished entry of a directory (node, two paths, future channel: about 1 KB each) until the whole directory has been walked, and only then folds them into the tree. A directory of 1M entries therefore needs about 1 GB on top of the tree.

Entries are folded in order, so this folds them in during the walk, keeping a window of 10000 so entries ahead of a slow one can still finish out of order. The file saver's channel is unbuffered, so this costs no concurrency. Directories under 10000 entries are unaffected.

Also:
- each entry's name is released once its paths are built;
- the tree buffer is sized from the entry count instead of being grown repeatedly, which held two copies at once. (`bytes.Buffer.Grow` is worse here: it allocates the new size alongside the old.)

One flat directory of zero-byte files, `GOMAXPROCS=2 GOGC=20`: 1M entries goes from 1248 MB to 773 MB peak RSS. Under a 600 MiB cap, 600,000 entries is killed before and completes after.

The tree written is unchanged: a second backup with `--force` into the same repository gives the same root tree id, `check --read-data` passes, and a restore matches the source. `TestArchiverSaveDirWide` covers a directory wider than the window, with entries finishing out of order.

Measured with https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro (peak RSS from `VmHWM`, caps via cgroup). When reproducing: compare tree ids within one repository only, since each repository has its own chunker polynomial; and use `VmHWM` rather than cgroup memory, which includes page cache.

> **How this was written:** I'm an engineer, not a Go developer. I use restic to back up WordPress sites, which can hold very large numbers of thumbnails in one directory. An AI assistant wrote this code; it solves my case, but I don't claim it's the right solution, and there are use cases I can't anticipate without Go experience. The numbers are my own measurements; the change passes the existing test suite plus the tests added here, and has run on real backups. Happy to rework it in whatever direction you prefer.

## Was the change previously discussed in an issue or on the forum?

#2446

## Checklist

- [x] I have added tests for all code changes
- [ ] I have added documentation for relevant changes (in the manual)
- [x] There's a new file in `changelog/unreleased/`
- [x] I'm done! This pull request is ready for review.
