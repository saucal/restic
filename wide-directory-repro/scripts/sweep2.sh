#!/bin/bash
set -u
run() { TOTAL=$1 PERDIR=$2 SIZE=$3 LABEL=$4 /run.sh 2>&1 | grep -E "^== RESULT"; }
run 400000  0    0 flat-400k
run 1000000 0    0 flat-1M
run 400000  1000 0 spread-400k-1k
