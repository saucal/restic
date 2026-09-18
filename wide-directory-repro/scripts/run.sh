#!/bin/bash
# Measures restic backup's peak RSS for a synthetic tree. One run per container.
# TOTAL files, PERDIR files per directory, SIZE bytes each.
set -u
TOTAL=${TOTAL:-100000}
PERDIR=${PERDIR:-0}
SIZE=${SIZE:-0}
LABEL=${LABEL:-run}

export RESTIC_PASSWORD=test
export RESTIC_REPOSITORY=/repo
# Match what the fleet actually runs on the WP hosts.
export GOMAXPROCS=${GOMAXPROCS:-2}
export GOGC=${GOGC:-20}

rm -rf /data /repo && mkdir -p /data /repo
echo "== generating: total=$TOTAL per-dir=$PERDIR size=$SIZE"
/bin/gen -root /data -total "$TOTAL" -per-dir "$PERDIR" -size "$SIZE"
echo "== tree on disk: $(du -sh /data | cut -f1), dirs: $(find /data -mindepth 1 -type d | wc -l)"

/bin/restic init >/dev/null 2>&1

# VmHWM is the kernel's own peak-RSS counter for the process, so polling it
# cannot miss a spike between samples.
/bin/restic backup /data --no-scan > /tmp/backup.log 2>&1 &
pid=$!
hwm=0
while kill -0 $pid 2>/dev/null; do
  v=$(sed -n "s/^VmHWM:[[:space:]]*\([0-9]*\).*/\1/p" /proc/$pid/status 2>/dev/null)
  [ -n "${v:-}" ] && hwm=$v
  sleep 0.2
done
wait $pid; rc=$?
echo "== RESULT label=$LABEL total=$TOTAL per_dir=$PERDIR size=$SIZE peak_rss_kb=$hwm peak_rss_mb=$((hwm/1024)) exit=$rc"
tail -4 /tmp/backup.log
