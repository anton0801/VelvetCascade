#!/bin/zsh
# Скриншот DEBUG-фикстуры из работающей сборки: scripts/shot.sh <device-udid> <fixture> <out.png> [delay] [extra args...]
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV=$1; FX=$2; OUT=$3; DELAY=${4:-2.5}; shift 4 2>/dev/null
xcrun simctl terminate "$DEV" app.VelvetCascade >/dev/null 2>&1
xcrun simctl launch "$DEV" app.VelvetCascade -VCFixture "$FX" "$@" >/dev/null
sleep "$DELAY"
xcrun simctl io "$DEV" screenshot "$OUT" >/dev/null 2>&1 && echo "$OUT"
