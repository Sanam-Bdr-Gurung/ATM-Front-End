#!/usr/bin/env bash
# Pull the latest ChordAssist recording off a connected debug device and
# save it under a declared Tier-2 clip ID.
#
# Developer/data-collection utility only — NOT application functionality.
# It never analyzes the recording.
#
# Usage:
#   ./tool/pull_chordassist_recording.sh <clip_id> <destination_dir> [--force]
#
# Example:
#   ./tool/pull_chordassist_recording.sh exp_baseline_p1 \
#     ~/Documents/sanam/thesis/chordassist/backend/evaluation_data/application_robustness/audio
#
# The app keeps ONLY the latest recording (it overwrites the same file),
# so pull each clip BEFORE starting the next recording.
#
# The recording lives somewhere inside the app sandbox as exactly
# "chordassist_recording.wav"; the directory varies by device/Android
# version (Directory.systemTemp has resolved to cache/ on some devices
# and code_cache/ on others), so the script SEARCHES for the exact
# filename instead of hardcoding a path, and requires exactly one match.

set -euo pipefail

PACKAGE_ID="com.chords.finder.chords_finder"
RECORDING_BASENAME="chordassist_recording.wav"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Reads newline-separated candidate paths on stdin and applies the
# match policy for the current recording:
#   exactly one match  -> prints it, returns 0
#   zero matches       -> prints nothing, returns 2
#   multiple matches   -> prints all of them, returns 3
# Kept as a pure function so tool/test_pull_recording_selection.sh can
# exercise it without a device.
select_recording_path() {
  local matches count

  matches=$(grep -v '^[[:space:]]*$' || true)

  count=$(printf '%s' "$matches" | grep -c . || true)

  if [ "$count" -eq 0 ]; then
    return 2
  fi

  printf '%s' "$matches"

  if [ "$count" -gt 1 ]; then
    return 3
  fi

  return 0
}

# Library mode for the selection-logic tests: stop before any device
# interaction.
if [ "${PULL_SCRIPT_LIB:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

[ "$#" -ge 2 ] || die "usage: $0 <clip_id> <destination_dir> [--force]"

CLIP_ID="$1"
DEST_DIR="$2"
FORCE="${3:-}"

case "$CLIP_ID" in
  *[!a-zA-Z0-9_]*) die "clip_id may contain only letters, digits and _" ;;
esac

command -v adb >/dev/null 2>&1 || die "adb not found on PATH"

# Exactly one usable device.
DEVICES=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
DEVICE_COUNT=$(printf '%s' "$DEVICES" | grep -c . || true)

if [ "$DEVICE_COUNT" -eq 0 ]; then
  die "no usable ADB device found (check USB debugging and authorization)"
elif [ "$DEVICE_COUNT" -gt 1 ]; then
  die "multiple ADB devices connected — disconnect all but one:
$DEVICES"
fi

# Search the app sandbox for the exact recording filename. Only the
# exact basename is a valid identifier: picked-file cache copies (e.g.
# cache/<uuid>/dev_clean_01.wav) must never match.
CANDIDATES=$(adb shell run-as "$PACKAGE_ID" \
  find . -type f -name "$RECORDING_BASENAME" 2>/dev/null | tr -d '\r' || true)

set +e
DEVICE_FILE=$(printf '%s\n' "$CANDIDATES" | select_recording_path)
SELECT_RC=$?
set -e

if [ "$SELECT_RC" -eq 2 ]; then
  die "no current recording found ($RECORDING_BASENAME is not present in
$PACKAGE_ID's sandbox). Record in ChordAssist first (debug build required
for run-as)."
elif [ "$SELECT_RC" -eq 3 ]; then
  die "multiple '$RECORDING_BASENAME' files found in the app sandbox —
resolve the ambiguity manually (adb shell run-as $PACKAGE_ID ls/rm):
$DEVICE_FILE"
elif [ "$SELECT_RC" -ne 0 ]; then
  die "recording search failed (rc=$SELECT_RC)"
fi

mkdir -p "$DEST_DIR"
DEST_FILE="$DEST_DIR/$CLIP_ID.wav"

if [ -e "$DEST_FILE" ] && [ "$FORCE" != "--force" ]; then
  die "$DEST_FILE already exists — refusing to overwrite.
Pass --force only if you deliberately want to replace it."
fi

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/chordassist_pull.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

adb exec-out run-as "$PACKAGE_ID" cat "$DEVICE_FILE" > "$TMP_FILE"

SIZE_BYTES=$(wc -c < "$TMP_FILE" | tr -d ' ')

# A WAV header alone is 44 bytes; anything near that is an empty take.
[ "$SIZE_BYTES" -gt 1000 ] || die "pulled file is only ${SIZE_BYTES} bytes — recording looks empty"

mv "$TMP_FILE" "$DEST_FILE"
trap - EXIT

SHA256=$(shasum -a 256 "$DEST_FILE" | awk '{print $1}')

echo "device path: $DEVICE_FILE"
echo "saved:       $DEST_FILE"
echo "size:        $SIZE_BYTES bytes"
echo "sha256:      $SHA256"
echo
echo "manifest entry values:"
echo "  \"audio_path\": \"evaluation_data/application_robustness/audio/$CLIP_ID.wav\","
echo "  \"sha256\": \"$SHA256\","
echo
echo "Next: annotate the clip BEFORE running any prediction, then add the"
echo "manifest entry. This script never analyzes the recording."
