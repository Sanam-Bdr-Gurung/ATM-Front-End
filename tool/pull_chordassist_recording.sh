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
# The app keeps ONLY the latest recording (it overwrites the same cache
# file), so pull each clip BEFORE starting the next recording.

set -euo pipefail

PACKAGE_ID="com.chords.finder.chords_finder"
DEVICE_FILE="cache/chordassist_recording.wav"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

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

# The recording must exist in the debug app's private cache.
if ! adb shell run-as "$PACKAGE_ID" ls "$DEVICE_FILE" >/dev/null 2>&1; then
  die "no recording found at $DEVICE_FILE inside $PACKAGE_ID.
Record in ChordAssist first (this must be a debug build for run-as)."
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

echo "saved:      $DEST_FILE"
echo "size:       $SIZE_BYTES bytes"
echo "sha256:     $SHA256"
echo
echo "manifest entry values:"
echo "  \"audio_path\": \"evaluation_data/application_robustness/audio/$CLIP_ID.wav\","
echo "  \"sha256\": \"$SHA256\","
echo
echo "Next: annotate the clip BEFORE running any prediction, then add the"
echo "manifest entry. This script never analyzes the recording."
