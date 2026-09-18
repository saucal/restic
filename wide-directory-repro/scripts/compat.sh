#!/bin/bash
# Written by the patched build (spilling + streaming), read back by pristine
# upstream v0.19.1. 60000 entries puts the wide directory over spillTreeEntries.
set -u
export RESTIC_PASSWORD=test GOMAXPROCS=2 GOGC=20 RESTIC_REPOSITORY=/repo
rm -rf /src /repo /out-new /out-old && mkdir -p /src /repo
/bin/gen -root /src -total 60000 -per-dir 0 -size 0 >/dev/null
i=0; for f in $(find /src -type f | head -30); do i=$((i+1)); head -c $((i*140000)) /dev/urandom > "$f"; done
mkdir -p /src/d00000/sub/deep && echo hi > /src/d00000/sub/deep/x && ln -s x /src/d00000/sub/deep/link

/bin/restic-ship3 init >/dev/null 2>&1
echo "--- backup WRITTEN by the patched build:"
/bin/restic-ship3 backup /src --no-scan 2>&1 | tail -2

echo "--- pristine v0.19.1 version:"; /bin/restic-pristine version
echo "--- pristine: check --read-data"
/bin/restic-pristine check --read-data 2>&1 | tail -2
echo "--- pristine: ls counts entries"
echo "  entries listed: $(/bin/restic-pristine ls latest --recursive 2>/dev/null | wc -l)"
echo "--- pristine: cat the wide directory's tree blob and count nodes"
root=$(/bin/restic-pristine snapshots --json 2>/dev/null | grep -o '"tree":"[0-9a-f]\{64\}"' | grep -o '[0-9a-f]\{64\}' | head -1)
sub=$(/bin/restic-pristine cat tree "$root" 2>/dev/null | grep -o '"subtree":"[0-9a-f]\{64\}"' | grep -o '[0-9a-f]\{64\}' | head -1)
wide=$(/bin/restic-pristine cat tree "$sub" 2>/dev/null | grep -o '"subtree":"[0-9a-f]\{64\}"' | grep -o '[0-9a-f]\{64\}' | head -1)
echo "  nodes in the wide tree: $(/bin/restic-pristine cat tree "$wide" 2>/dev/null | grep -o '"name":' | wc -l)"
echo "--- pristine: restore, then diff against the source"
/bin/restic-pristine restore latest --target /out-old >/dev/null 2>&1 && diff -r /src /out-old/src >/dev/null 2>&1 && echo "  PRISTINE RESTORE MATCHES SOURCE EXACTLY" || echo "  PRISTINE RESTORE MISMATCH"
echo "--- and the reverse: pristine writes, patched build reads"
/bin/restic-pristine backup /src --no-scan --force 2>&1 | tail -1
echo "  unique root trees across both snapshots (1 line == both builds wrote the same tree):"
/bin/restic-ship3 snapshots --json 2>/dev/null | tr '{' '\n' | grep -o '"tree":"[0-9a-f]*"' | sort -u
/bin/restic-ship3 check --read-data 2>&1 | tail -1
