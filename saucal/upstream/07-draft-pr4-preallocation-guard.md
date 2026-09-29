<!-- POST AS: a DRAFT pull request
     TITLE:  restore: Don't hang on a filesystem that never preallocates
     BRANCH: upstream/pr4-preallocation-guard  ->  restic/restic:master  (1 commit, self-contained) -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

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
already lost. A deadline-based version was tried first and does not work for this
reason.

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

The awkward part is re-execing the binary to ask the question, and the hidden
argument that makes it possible. The difficulty is that any way of asking within
the process can take that process with it; if there is a way to ask that does not,
it would be better than this. `internal/fileio/preallocate_probe_test.go` covers
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

Closes #<issue b>.
