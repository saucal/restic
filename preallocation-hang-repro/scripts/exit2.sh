#!/bin/sh
set -u
export RESTIC_REPOSITORY=/work/repo RESTIC_PASSWORD=test
rm -rf /work/repo /work/data /work/backing /work/mnt
mkdir -p /work/data /work/backing /work/mnt
dd if=/dev/urandom of=/work/data/a.bin bs=1M count=8 status=none
/work/restic-probe init -q >/dev/null
/work/restic-probe backup -q /work/data >/dev/null
/work/hangfs-linux-arm64 /work/backing /work/mnt 2>/dev/null &
sleep 2
/work/restic-probe restore latest --target /work/mnt/restore &
echo $! > /work/restic.pid
sleep 1000
