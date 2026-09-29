#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build-app.sh [--install] [--universal] [--dmg] [--test]

  (no flags)   build .build/WhyPort.app for this Mac
  --install    copy it to /Applications and open it
  --universal  build for Apple Silicon and Intel
  --dmg        also package .build/WhyPort.dmg
  --test       run the core checks and exit
EOF
}

INSTALL=0 UNIVERSAL=0 DMG=0 TEST=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --dmg) DMG=1 ;;
    --test) TEST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

cd "$(dirname "$0")"
BUILD=".build/manual"
APP=".build/WhyPort.app"
mkdir -p "$BUILD"

# Command Line Tools can ship an SDK newer than its compiler, so pick the newest SDK this swiftc accepts.
pick_sdk() {
  local probe="$BUILD/probe.swift"
  printf 'import SwiftUI\n' > "$probe"
  local candidates=()
  [[ -n "${SDKROOT:-}" ]] && candidates+=("$SDKROOT")
  candidates+=("$(xcrun --show-sdk-path 2>/dev/null || true)")
  while IFS= read -r sdk; do candidates+=("$sdk"); done < <(ls -d "$(xcode-select -p)"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV)
  for sdk in "${candidates[@]}"; do
    [[ -d "$sdk" ]] || continue
    if swiftc -sdk "$sdk" -typecheck "$probe" >/dev/null 2>&1; then
      echo "$sdk"
      return
    fi
  done
  echo "No macOS SDK works with $(swiftc --version 2>&1 | head -1)" >&2
  exit 1
}

SDK="$(pick_sdk)"

build_arch() {
  local arch="$1" out="$BUILD/$1"
  mkdir -p "$out"
  local flags=(-sdk "$SDK" -target "$arch-apple-macos14.0" -O -swift-version 5)
  swiftc "${flags[@]}" -parse-as-library -enable-testing \
    -module-name WhyPortCore -emit-library -static \
    -emit-module -emit-module-path "$out/WhyPortCore.swiftmodule" \
    -o "$out/libWhyPortCore.a" Sources/WhyPortCore/*.swift
  if [[ "$TEST" == 1 ]]; then
    swiftc "${flags[@]}" -parse-as-library \
      -module-name WhyPortChecks -I "$out" -L "$out" -lWhyPortCore \
      -o "$out/WhyPortChecks" Checks/*.swift
    "$out/WhyPortChecks"
    return
  fi
  swiftc "${flags[@]}" -parse-as-library \
    -module-name WhyPort -I "$out" -L "$out" -lWhyPortCore \
    -o "$out/WhyPort" Sources/WhyPort/*.swift
}

NATIVE="$(uname -m)"
if [[ "$TEST" == 1 ]]; then
  build_arch "$NATIVE"
  exit 0
fi

if [[ "$UNIVERSAL" == 1 ]]; then
  build_arch arm64
  build_arch x86_64
  lipo -create "$BUILD/arm64/WhyPort" "$BUILD/x86_64/WhyPort" -output "$BUILD/WhyPort"
else
  build_arch "$NATIVE"
  cp "$BUILD/$NATIVE/WhyPort" "$BUILD/WhyPort"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/WhyPort" "$APP/Contents/MacOS/WhyPort"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${WHYPORT_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${WHYPORT_VERSION#v}" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "$DMG" == 1 ]]; then
  STAGE="$BUILD/dmg"
  rm -rf "$STAGE" .build/WhyPort.dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/WhyPort.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname WhyPort -srcfolder "$STAGE" -ov -format UDZO .build/WhyPort.dmg >/dev/null
  echo "Packaged .build/WhyPort.dmg"
fi

if [[ "$INSTALL" == 1 ]]; then
  pkill -x WhyPort 2>/dev/null || true
  rm -rf /Applications/WhyPort.app
  cp -R "$APP" /Applications/WhyPort.app
  open /Applications/WhyPort.app
  echo "Installed /Applications/WhyPort.app"
fi
