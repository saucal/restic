#!/bin/sh
set -u
exec >/work/log-twice.txt 2>&1
export RESTIC_REPOSITORY=/work/repo RESTIC_PASSWORD=test
rm -rf /work/repo /work/data /work/backing /work/mnt
mkdir -p /work/data /work/backing /work/mnt
dd if=/dev/urandom of=/work/data/a.bin bs=1M count=16 status=none
dd if=/dev/urandom of=/work/data/b.bin bs=1M count=4 status=none
( cd /work/data && sha256sum * > /work/sums.txt )
/work/restic-final init -q
/work/restic-final backup -q /work/data
/work/hangfs-linux-arm64 /work/backing /work/mnt 2>/work/hangfs2.log &
FS=$!
sleep 2
for pass in 1 2 3; do
    echo "=== restore pass $pass ==="
    START=$(date +%s)
    timeout -s KILL 90 /work/restic-final restore latest --target /work/mnt/restore --overwrite always
    echo "pass $pass exit=$? after $(( $(date +%s) - START ))s"
done
echo "=== preallocation calls the filesystem saw in total ==="
grep -c fallocate /work/hangfs2.log
kill -9 $FS 2>/dev/null; sleep 1
echo "=== integrity ==="
( cd /work/backing/restore/work/data && sha256sum -c /work/sums.txt )
