#!/usr/bin/env bash
# Regression tests for the recording-selection policy in
# pull_chordassist_recording.sh. Runs entirely without a device by
# sourcing the script in library mode.
#
# Usage: ./tool/test_pull_recording_selection.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# shellcheck source=pull_chordassist_recording.sh
PULL_SCRIPT_LIB=1 . "$SCRIPT_DIR/pull_chordassist_recording.sh"

# The sourced script enables -e; the harness must observe non-zero
# returns instead of dying on them.
set +e

PASS=0
FAIL=0

check() {
  local name=$1 want_rc=$2 want_out=$3 input=$4
  local out rc

  out=$(printf '%s\n' "$input" | select_recording_path)
  rc=$?

  if [ "$rc" -eq "$want_rc" ] && [ "$out" = "$want_out" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (rc=$rc want=$want_rc; out='$out')"
    FAIL=$((FAIL + 1))
  fi
}

check "recording under cache/" 0 \
  "./cache/chordassist_recording.wav" \
  "./cache/chordassist_recording.wav"

check "recording under code_cache/" 0 \
  "./code_cache/chordassist_recording.wav" \
  "./code_cache/chordassist_recording.wav"

check "zero matches" 2 "" ""

check "zero matches (blank lines only)" 2 "" "

"

MULTI="./cache/chordassist_recording.wav
./code_cache/chordassist_recording.wav"

check "multiple exact-name matches" 3 "$MULTI" "$MULTI"

echo
echo "$PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ]
