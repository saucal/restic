<!-- PULL REQUEST, ready for review. Branch upstream/pr4-preallocation-guard -> restic/restic:master
     Title: restore: Don't hang on a filesystem that never preallocates -->

## What does this PR change? What problem does it solve?

Closes #<issue>. One commit, self-contained; unrelated to #2446.

`fallocate` can be accepted by a filesystem and never return. The calling thread then can't be interrupted, not even by `SIGKILL`, and the file's inode stays locked, so a timeout around the call can't recover. Preallocation is optional, though: the file can be written without it. So the fix is to not make the call where it would hang. Details in #<issue>.

This asks first: a child process (the restic binary re-executed with a hidden `--__preallocate-probe <dir>` argument, handled at the top of `main` before flag parsing) preallocates a throwaway, already-unlinked file in the target directory. If it doesn't answer within 5 s, preallocation is skipped on that filesystem. The result is cached per filesystem. Both callers already treat a failed preallocation as harmless, so the restore continues without reserving space.

Re-executing the binary is the part I'm least sure of; I couldn't find an in-process way to ask that can't hang the process itself. Open to alternatives.

Tests in `internal/fileio/preallocate_probe_test.go`: a child that never answers, a binary that doesn't understand the argument, a reply without the expected token, a normal process ignoring the flag, the probe leaving no file behind, and a working filesystem still preallocating.

On the affected host, restores that hung now complete: a 30k-file tree in 14 s, a 10 GB tree in 40 s.

> **How this was written:** I'm an engineer, not a Go developer. I use restic to back up WordPress sites, which can hold very large numbers of thumbnails in one directory. An AI assistant wrote this code; it solves my case, but I don't claim it's the right solution, and there are use cases I can't anticipate without Go experience. The numbers are my own measurements; the change passes the existing test suite plus the tests added here, and has run on real backups. Happy to rework it in whatever direction you prefer.

## Was the change previously discussed in an issue or on the forum?

#<issue>

## Checklist

- [x] I have added tests for all code changes
- [ ] I have added documentation for relevant changes (in the manual)
- [x] There's a new file in `changelog/unreleased/`
- [x] I'm done! This pull request is ready for review.
