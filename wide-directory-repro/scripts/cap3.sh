#!/bin/bash
set -u
BIN=${BIN:-restic-ship}
FLAGS=${FLAGS:-}
export RESTIC_PASSWORD=test RESTIC_REPOSITORY=/repo GOMAXPROCS=2 GOGC=20
rm -rf /repo && mkdir -p /repo
/bin/$BIN init >/dev/null 2>&1
/bin/$BIN backup /data --no-scan $FLAGS > /tmp/b.log 2>&1 &
pid=$!
hwm=0
while kill -0 $pid 2>/dev/null; do
  v=$(sed -n "s/^VmHWM:[[:space:]]*\([0-9]*\).*/\1/p" /proc/$pid/status 2>/dev/null)
  [ -n "${v:-}" ] && hwm=$v
  sleep 0.2
done
wait $pid; rc=$?
verdict=KILLED; grep -qE "snapshot .* saved" /tmp/b.log && verdict=SURVIVED
echo "CAPRESULT bin=$BIN flags='$FLAGS' cap=${CAPLABEL:-none} peak_rss_mb=$((hwm/1024)) exit=$rc verdict=$verdict"
