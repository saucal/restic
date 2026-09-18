#!/bin/bash
# 60000 entries: above spillTreeEntries, so the new build takes the temp-file
# streaming path while the old one buffers. Same repo, so tree IDs compare.
set -u
export RESTIC_PASSWORD=test GOMAXPROCS=2 GOGC=20 RESTIC_REPOSITORY=/repo
rm -rf /src /repo && mkdir -p /src /repo
/bin/gen -root /src -total 60000 -per-dir 0 -size 0 >/dev/null
i=0; for f in $(find /src -type f | head -40); do i=$((i+1)); head -c $((i*130000)) /dev/urandom > "$f"; done
mkdir -p /src/d00000/nested/deeper && echo hi > /src/d00000/nested/deeper/x && ln -s x /src/d00000/nested/deeper/link
/bin/restic-old init >/dev/null 2>&1
echo "--- OLD (buffered):"; /bin/restic-old backup /src --no-scan 2>&1 | tail -2
echo "--- NEW (spilled+streamed), --force:"; /bin/restic-ship2 backup /src --no-scan --force 2>&1 | tail -3
echo "--- unique root trees across both snapshots (1 line == identical):"
/bin/restic-ship2 snapshots --json 2>/dev/null | tr '{' '\n' | grep -o '"tree":"[0-9a-f]*"' | sort -u
echo "--- check --read-data:"; /bin/restic-ship2 check --read-data 2>&1 | tail -2
echo "--- restore and diff against source:"
/bin/restic-ship2 restore latest --target /out >/dev/null 2>&1 && diff -r /src /out/src >/dev/null 2>&1 && echo "restore matches source EXACTLY" || echo "RESTORE MISMATCH"
