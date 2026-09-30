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

  SIGN_IDENTITY="Developer ID Application: ..."  sign for distribution
  instead of ad-hoc, with the hardened runtime notarization needs.
  See docs/APPLE.md for the full Apple Developer setup.
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
ENTITLEMENTS="WhyPort.entitlements"
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

sign_app() {
  local target="$1"
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" \
      "$target/Contents/MacOS/WhyPort"
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" \
      "$target"
    codesign --verify --deep --strict --verbose=2 "$target"
    echo "Signed with $SIGN_IDENTITY (hardened runtime)"
  else
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$target" >/dev/null
  fi
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
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f Resources/PrivacyInfo.xcprivacy ]]; then
  cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
fi
if [[ -n "${WHYPORT_VERSION:-}" ]]; then
  version="${WHYPORT_VERSION#v}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$APP/Contents/Info.plist"
fi
sign_app "$APP"
echo "Built $APP"

if [[ "$DMG" == 1 ]]; then
  DMG_PATH=".build/WhyPort.dmg"
  rm -f "$DMG_PATH"
  VENV=".build/venv"
  if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
    python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild || rm -rf "$VENV"
  fi
  if [[ -x "$VENV/bin/dmgbuild" ]]; then
    "$VENV/bin/dmgbuild" -s ../packaging/dmg/settings.py \
      -D app="$APP" -D background=Resources/dmg-background.tiff -D icon=Resources/AppIcon.icns \
      WhyPort "$DMG_PATH" >/dev/null
  else
    echo "dmgbuild unavailable, packaging a plain disk image" >&2
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/WhyPort.app"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname WhyPort -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
  fi
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  fi
  echo "Packaged $DMG_PATH"
fi

if [[ "$INSTALL" == 1 ]]; then
  pkill -x WhyPort 2>/dev/null || true
  rm -rf /Applications/WhyPort.app
  cp -R "$APP" /Applications/WhyPort.app
  open /Applications/WhyPort.app
  echo "Installed /Applications/WhyPort.app"
fi
