#!/bin/sh
# One phase of the reproduction. Everything is logged to /work/log-$NAME.txt so the
# host can read it even if this container has to be killed.
set -u
BIN="$1"; NAME="$2"; LIMIT="${3:-40}"
LOG=/work/log-$NAME.txt
exec >"$LOG" 2>&1
set -x
cd /work
export RESTIC_REPOSITORY=/work/repo RESTIC_PASSWORD=test

rm -rf /work/repo /work/data /work/backing /work/mnt
mkdir -p /work/data /work/backing /work/mnt
dd if=/dev/urandom of=/work/data/a.bin bs=1M count=8 status=none
dd if=/dev/urandom of=/work/data/b.bin bs=1M count=8 status=none

"$BIN" version
"$BIN" init -q
"$BIN" backup -q /work/data

./hangfs-linux-arm64 /work/backing /work/mnt &
sleep 2

set +x
echo "=== restore begins $(date +%T), limit ${LIMIT}s ==="
START=$(date +%s)
# SIGQUIT first: Go dumps every goroutine stack, which shows where it is stuck.
timeout -s QUIT "$LIMIT" "$BIN" restore latest --target /work/mnt/restore
echo "=== exit=$? after $(( $(date +%s) - START ))s ==="
echo "=== what landed in the target ==="
ls -l /work/mnt/restore/work/data 2>&1
echo "=== byte counts (sizes above can lie on a mount) ==="
for f in /work/mnt/restore/work/data/*; do printf '%s ' "$f"; timeout 5 wc -c <"$f" 2>&1 || echo "(read timed out)"; done
