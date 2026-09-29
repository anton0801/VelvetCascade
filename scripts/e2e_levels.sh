#!/bin/zsh
# Сквозная проверка: проигрывает solutionTrace уровней внутри приложения (commit → анимация → результат).
# scripts/e2e_levels.sh <udid> [--reduce-motion] <level ids...>
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV=$1; shift
EXTRA=()
if [ "$1" = "--reduce-motion" ]; then EXTRA=(-VCReduceMotion); shift; fi
C=$(xcrun simctl get_app_container $DEV app.VelvetCascade data)
for L in "$@"; do
  rm -f "$C/Documents/outcome-$L.txt"
  xcrun simctl terminate $DEV app.VelvetCascade >/dev/null 2>&1
  xcrun simctl launch $DEV app.VelvetCascade -VCFixture level_$(printf %03d $L | sed 's/^0*//') -VCScript solveall "${EXTRA[@]}" >/dev/null
  for i in $(seq 1 120); do
    [ -f "$C/Documents/outcome-$L.txt" ] && break
    sleep 1
  done
  echo "L$L: $(cat "$C/Documents/outcome-$L.txt" 2>/dev/null || echo 'NO OUTCOME (timeout)')"
done
