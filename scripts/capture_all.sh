#!/bin/zsh
# Скриншоты всех DEBUG-фикстур из работающей сборки в docs/screenshots/<label>/.
# scripts/capture_all.sh <device-udid> <label> [extra launch args...]
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV=$1; LABEL=$2; shift 2
cd "$(dirname "$0")/.."
OUT=docs/screenshots/$LABEL
mkdir -p $OUT
FIXTURES=(welcome match rotate home_new home_resume home_complete worlds_new worlds_mid worlds_all map_mid map_locked
  brief_new brief_replay brief_invalid game_6x6 game_8x8 game_ring game_split game_q1 game_q2 game_q3 game_moves1 game_hc
  game_hint game_tutorial preview_key preview_split pause restart_confirm win_3 win_2 win_1_repeat win_20 win_180 win_cap fail
  new_theatre final_bow daily_ready daily_collected daily_restored daily_error reward_mixed reward_pair reward_triple reward_cap
  rules handbook_matches handbook_stageTurn handbook_curtainSweep handbook_keysExits handbook_velvetPlates handbook_crates
  handbook_ice handbook_chains handbook_shutters handbook_specials handbook_dailyEncore settings credits import_valid import_run
  reset recovery_save recovery_import recovery_level recovery_restore gallery_1 gallery_2 gallery_3 gallery_4)
for f in $FIXTURES; do
  xcrun simctl terminate "$DEV" app.VelvetCascade >/dev/null 2>&1
  xcrun simctl launch "$DEV" app.VelvetCascade -VCFixture "$f" "$@" >/dev/null
  case $f in handbook_*) sleep 4.0;; *) sleep 2.6;; esac
  xcrun simctl io "$DEV" screenshot "$OUT/$f.png" >/dev/null 2>&1
done
echo "captured ${#FIXTURES} fixtures to $OUT"
