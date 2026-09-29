#!/bin/zsh
# Кадры посреди анимации из работающей сборки: поворот, извлечение ключа, каскад.
# scripts/capture_moments.sh <udid>
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV=$1
cd "$(dirname "$0")/.."
OUT=docs/screenshots/moments; mkdir -p $OUT
shoot() { # fixture script delay out
  xcrun simctl terminate $DEV app.VelvetCascade >/dev/null 2>&1
  xcrun simctl launch $DEV app.VelvetCascade -VCFixture "$1" -VCScript "$2" >/dev/null
  sleep "$3"; xcrun simctl io $DEV screenshot "$OUT/$4.png" >/dev/null 2>&1
}
shoot preview_key "turn" 1.75 moment_rotation
shoot level_21 "solve:0;wait:2.5;solve:1" 7.4 moment_key_extraction
shoot game_6x6 "swap:5,2>4,2" 1.55 moment_cascade
ls $OUT
