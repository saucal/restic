#!/bin/sh
# What does preallocation buy on a real ext4 filesystem? Restore the same snapshot
# with and without it, then count extents and measure a sequential read.
set -u
exec >/work/log-frag.txt 2>&1
set -x
apk add --no-cache e2fsprogs e2fsprogs-extra >/dev/null 2>&1
set +x

IMG=/var/tmp/ext4.img
MNT=/mnt/ext4
mkdir -p "$MNT" /var/tmp/src
dd if=/dev/zero of="$IMG" bs=1M count=6144 status=none
mkfs.ext4 -q -F "$IMG"

export RESTIC_REPOSITORY=/var/tmp/repo RESTIC_PASSWORD=test
rm -rf /var/tmp/repo /var/tmp/src; mkdir -p /var/tmp/src
# one large file (the VM-image case preallocation was added for) plus smaller ones
dd if=/dev/urandom of=/var/tmp/src/big.bin bs=1M count=1024 status=none
for i in 1 2 3 4; do dd if=/dev/urandom of=/var/tmp/src/med$i.bin bs=1M count=128 status=none; done
/work/restic-guard init -q
/work/restic-guard backup -q /var/tmp/src

run() { # $1 = label, $2 = 1 to disable preallocation
    mount -o loop "$IMG" "$MNT"
    rm -rf "$MNT/r"; mkdir -p "$MNT/r"
    echo "=== $1 ==="
    START=$(date +%s.%N)
    if [ "$2" = "1" ]; then
        RESTIC_NO_PREALLOCATE=1 /work/restic-guard restore latest --target "$MNT/r" >/dev/null
    else
        /work/restic-guard restore latest --target "$MNT/r" >/dev/null
    fi
    END=$(date +%s.%N)
    echo "$1 restore wall time: $(echo "$END - $START" | bc)s"
    sync
    for f in "$MNT"/r/var/tmp/src/big.bin "$MNT"/r/var/tmp/src/med1.bin; do
        echo "$1 $(basename $f): $(filefrag "$f" | sed 's/.*: //')"
    done
    umount "$MNT"                     # drops this filesystem's page cache
    mount -o loop "$IMG" "$MNT"
    START=$(date +%s.%N)
    dd if="$MNT"/r/var/tmp/src/big.bin of=/dev/null bs=1M status=none
    END=$(date +%s.%N)
    echo "$1 sequential read of big.bin: $(echo "$END - $START" | bc)s"
    sha256sum "$MNT"/r/var/tmp/src/big.bin
    umount "$MNT"
}

run "with-preallocation" 0
run "without-preallocation" 1
run "with-preallocation-again" 0
echo "=== source checksum ==="
sha256sum /var/tmp/src/big.bin
