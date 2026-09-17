#!/bin/sh
# Does the optimization still happen where it works? Compare extents on real ext4
# against a run with preallocation forced off by a filesystem that never answers.
set -u
exec >/work/log-healthy.txt 2>&1
apk add --no-cache e2fsprogs e2fsprogs-extra >/dev/null 2>&1
IMG=/var/tmp/ext4.img; MNT=/mnt/ext4
mkdir -p "$MNT"
dd if=/dev/zero of="$IMG" bs=1M count=3072 status=none
mkfs.ext4 -q -F "$IMG"
export RESTIC_REPOSITORY=/var/tmp/repo RESTIC_PASSWORD=test
rm -rf /var/tmp/repo /var/tmp/src; mkdir -p /var/tmp/src
dd if=/dev/urandom of=/var/tmp/src/big.bin bs=1M count=512 status=none
/work/restic-final init -q
/work/restic-final backup -q /var/tmp/src

mount -o loop "$IMG" "$MNT"
mkdir -p "$MNT/r"
echo "=== restore onto healthy ext4 ==="
/work/restic-final restore latest --target "$MNT/r" 2>&1 | tail -2
sync
echo "extents: $(filefrag "$MNT"/r/var/tmp/src/big.bin | sed 's/.*: //')"
echo "blocks allocated: $(stat -c %b "$MNT"/r/var/tmp/src/big.bin), size: $(stat -c %s "$MNT"/r/var/tmp/src/big.bin)"
echo "leftover probe files: $(find "$MNT/r" -name '*preallocate-probe*' | wc -l)"
umount "$MNT"
