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

## A memory ceiling for backup

**Why:** elka cannot be backed up on Pressable — restic is OOM-killed. The
diagnostics added in `RESTIC_DIAG_LOG` say *what* it was using when it died;
they do not stop it happening.

**Shape:** honour `GOMEMLIMIT`, or a `--memory-limit` that throttles concurrency
and index residency to fit. Do this only once the diagnostics have said where the
memory actually goes — the answer may be index size, in which case the fix is a
different one.

## Deferred decisions, not features

* The preallocation fix has not been offered upstream. It needs an issue opened
  first (restic asks for prior discussion), which also replaces the placeholder
  number in its changelog entry.
* The minio CI fix (`upstream/ci-install-minio-from-source`) is a clean standalone
  contribution that would unblock everyone's test matrix; upstream currently has
  the same fix buried inside an unrelated feature PR (#22063).
