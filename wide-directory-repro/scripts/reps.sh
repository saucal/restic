#!/bin/bash
# One first backup to populate, then repeated re-backups: every tree is then
# already known, which is the case the two-pass change is meant to speed up.
set -u
BIN=${BIN:-restic-ship3}
REPS=${REPS:-3}
export RESTIC_PASSWORD=test RESTIC_REPOSITORY=/repo GOMAXPROCS=2 GOGC=20
rm -rf /repo && mkdir -p /repo
/bin/$BIN init >/dev/null 2>&1
ms() { date +%s%3N; }

a=$(ms); /bin/$BIN backup /data --no-scan >/tmp/b1.log 2>&1; b=$(ms)
echo "$BIN first_backup_ms=$((b-a))"
for i in $(seq 1 "$REPS"); do
  a=$(ms); /bin/$BIN backup /data --no-scan >/tmp/b2.log 2>&1; b=$(ms)
  echo "$BIN rebackup_${i}_ms=$((b-a))"
done
echo "  new data added on a re-backup: $(grep -oE 'Added to the repository: [^(]*' /tmp/b2.log | head -1)"
