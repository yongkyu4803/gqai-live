#!/bin/zsh
# Builds "GQAI Live.app" from source and installs it to ~/Applications.
#   mac/build.sh               build + install
#   mac/build.sh --no-install  build only (mac/build/GQAI Live.app)
# Environment:
#   MACOS_SDK=/path/to/MacOSX.sdk   when the default SDK doesn't match your Swift compiler
#   GQAI_BUNDLE_ID=...              default: kr.gqai.live
#   GQAI_PORT=7860                  must match config.env
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
CFG_PORT=$(grep -E '^GQAI_PORT=' "$ROOT/config.env" 2>/dev/null | cut -d= -f2 || true)
PORT="${GQAI_PORT:-${CFG_PORT:-7860}}"
BUNDLE_ID="${GQAI_BUNDLE_ID:-kr.gqai.live}"
SDK="${MACOS_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
APP="build/GQAI Live.app"
DEST="$HOME/Applications/GQAI Live.app"

mkdir -p build
swiftc -sdk "$SDK" -O -target "$(uname -m)-apple-macos14.2" Sources/*.swift -o build/GQAILive

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/GQAILive "$APP/Contents/MacOS/GQAILive"
sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|" -e "s|__PROJECT_PATH__|$ROOT|" -e "s|__PORT__|$PORT|" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature for personal use. Every rebuild changes it, so macOS may ask for the microphone and
# Accessibility permissions again (remove the old entry in System Settings and add the new app).
codesign --force --deep --sign - "$APP"
echo "빌드됨: $ROOT/mac/$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  if pgrep -fq "$DEST/Contents/MacOS/GQAILive"; then
    osascript -e 'quit app "GQAI Live"' >/dev/null 2>&1 || true
    for i in {1..20}; do pgrep -fq "$DEST/Contents/MacOS/GQAILive" || break; sleep 0.5; done
    if pgrep -fq "$DEST/Contents/MacOS/GQAILive"; then echo "GQAI Live가 실행 중입니다. 종료한 뒤 다시 실행하세요."; exit 1; fi
  fi
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "설치됨: $DEST"
fi
