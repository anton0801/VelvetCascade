#!/bin/zsh
# Сборка Debug для симулятора и установка: scripts/build_install.sh [device-udid]
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV=${1:-B0DE47DD-3DFB-44D9-82C1-CA52DC160646}
cd "$(dirname "$0")/.."
xcodebuild -project VelvetCascade.xcodeproj -scheme VelvetCascade -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath build/DerivedData build 2>&1 | grep -E "error:|BUILD" | sort -u
xcrun simctl install "$DEV" build/DerivedData/Build/Products/Debug-iphonesimulator/VelvetCascade.app && echo "installed on $DEV"
