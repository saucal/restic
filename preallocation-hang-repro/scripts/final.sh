#!/bin/sh
set -u
exec >/work/log-final.txt 2>&1
export RESTIC_REPOSITORY=/work/repo RESTIC_PASSWORD=test
rm -rf /work/repo /work/data /work/backing /work/mnt
mkdir -p /work/data /work/backing /work/mnt
dd if=/dev/urandom of=/work/data/big.bin bs=1M count=64 status=none
dd if=/dev/urandom of=/work/data/mid.bin bs=1M count=6 status=none
dd if=/dev/urandom of=/work/data/small.bin bs=1k count=9 status=none
printf '' > /work/data/empty.bin
mkdir -p /work/data/sub && dd if=/dev/urandom of=/work/data/sub/nested.bin bs=1M count=3 status=none
( cd /work/data && find . -type f | sort | xargs sha256sum > /work/sums.txt )

/work/restic-probe2 init -q
/work/restic-probe2 backup -q /work/data
/work/hangfs-linux-arm64 /work/backing /work/mnt 2>/work/hangfs.log &
FS=$!
sleep 2

echo "=== restore onto the hanging filesystem (killed at 120s if it hangs) ==="
START=$(date +%s)
timeout -s KILL 120 /work/restic-probe2 restore latest --target /work/mnt/restore
echo "restore exit=$? after $(( $(date +%s) - START ))s   <-- 137 would mean it never exited"

echo "=== how many times did the filesystem see a preallocation? ==="
grep -c "fallocate" /work/hangfs.log
echo "(each line below is one call it was asked to answer)"
cat /work/hangfs.log | grep fallocate

kill -9 $FS 2>/dev/null; sleep 1
echo "=== data integrity, checked off the mount ==="
( cd /work/backing/restore/work/data && sha256sum -c /work/sums.txt )
echo "=== leftovers? ==="
find /work/backing -name '*preallocate-probe*' | head
echo "(no lines above = nothing left behind)"
