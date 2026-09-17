#!/bin/sh
set -u
exec >/work/log-fsprobe.txt 2>&1
rm -rf /work/backing /work/mnt; mkdir -p /work/backing /work/mnt
/work/hangfs-linux-arm64 /work/backing /work/mnt &
sleep 2
echo "### on the hanging FUSE filesystem ###"
/work/fsprobe-linux-arm64 /work/mnt
echo
echo "### on a normal filesystem, for comparison ###"
/work/fsprobe-linux-arm64 /tmp
