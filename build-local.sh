#!/bin/bash
# Builds MTMR without Xcode, with Command Line Tools only (swiftc + clang).
#   ./build-local.sh                  -> "build/TouchBar Cats.app" for Apple Silicon
#   ARCH=x86_64 ./build-local.sh      -> Intel
#   ARCH=universal ./build-local.sh   -> both in one app
set -euo pipefail

cd "$(dirname "$0")"
SRC=MTMR
OUT=build
APP="$OUT/TouchBar Cats.app"
OBJ="$OUT/obj"
ARCH=${ARCH:-arm64}

# Take the newest SDK built by the same (or older) Swift as swiftc:
# after a Command Line Tools update the SDK can be newer than the compiler and the build fails.
SWIFT_VER=$(swiftc --version 2>&1 | sed -nE 's/.*Apple Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)
SDK=""
for s in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.*.sdk 2>/dev/null | sort -rV); do
    v=$(sed -nE 's/.*Apple Swift version ([0-9]+\.[0-9]+).*/\1/p' \
        "$s/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface" 2>/dev/null | head -1)
    if [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$v" "$SWIFT_VER" | sort -V | tail -1)" = "$SWIFT_VER" ]; then
        SDK="$s"; break
    fi
done
SDK=${SDK:-$(xcrun --show-sdk-path)}
echo "SDK: $SDK (swiftc $SWIFT_VER)"
PRIV="$SDK/System/Library/PrivateFrameworks"

case "$ARCH" in
    universal) ARCHS="arm64 x86_64" ;;
    arm64 | x86_64) ARCHS="$ARCH" ;;
    *) echo "Unknown ARCH=$ARCH (use arm64, x86_64 or universal)"; exit 1 ;;
esac

rm -rf "$OUT"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Resources"

binaries=()
for arch in $ARCHS; do
    TARGET="$arch-apple-macos11.0"
    mkdir -p "$OBJ/$arch"
    echo "==> C / Objective-C ($arch)"
    for f in "$SRC"/CBridge/*.m "$SRC"/CBridge/*.c; do
        clang -c -fobjc-arc -fmodules -O2 -target "$TARGET" -isysroot "$SDK" \
            -Wno-deprecated-declarations \
            "$f" -o "$OBJ/$arch/$(basename "${f%.*}").o"
    done

    echo "==> Swift ($arch)"
    swiftc -O -swift-version 5 -target "$TARGET" -sdk "$SDK" \
        -import-objc-header "$SRC/CBridge/TouchBarPrivateApi-Bridging.h" \
        -I "$SRC/CBridge" -F "$PRIV" \
        -suppress-warnings \
        $(find "$SRC" -name '*.swift') "$OBJ/$arch"/*.o \
        -framework Cocoa -framework IOKit -framework CoreAudio -framework AudioToolbox \
        -framework DFRFoundation -framework MultitouchSupport \
        -framework CoreBrightness -framework DisplayServices \
        -framework AVFoundation \
        -o "$OBJ/MTMR-$arch"
    binaries+=("$OBJ/MTMR-$arch")
done
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/MTMR"

echo "==> Resources"
RES="$APP/Contents/Resources"
cp "$SRC"/AppleScripts/*.scpt "$SRC/defaultPreset.json" "$RES/"
# Asset catalog images go in as plain files: NSImage(named:) finds them without actool
for set in "$SRC"/Assets.xcassets/*.imageset; do
    name=$(basename "$set" .imageset)
    img=$(find "$set" -name '*.png' -o -name '*.pdf' | head -1)
    cp "$img" "$RES/$name.${img##*.}"
done
ICONSET="$OBJ/AppIcon.iconset"
mkdir -p "$ICONSET"
A="$SRC/Assets.xcassets/AppIcon.appiconset"
for s in 16 32 128 256 512; do
    cp "$A/logo-$s.png" "$ICONSET/icon_${s}x${s}.png"
    cp "$A/logo-$((s * 2)).png" "$ICONSET/icon_${s}x${s}@2x.png" 2>/dev/null || true
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

echo "==> Info.plist"
PL="$APP/Contents/Info.plist"
sed -e 's/$(DEVELOPMENT_LANGUAGE)/en/' \
    -e 's/$(EXECUTABLE_NAME)/MTMR/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/local.MTMR/' \
    -e 's/$(PRODUCT_NAME)/TouchBar Cats/' \
    -e 's/$(MACOSX_DEPLOYMENT_TARGET)/11.0/' \
    "$SRC/Info.plist" > "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$PL"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TouchBar Cats" "$PL"
for k in NSMainStoryboardFile SUFeedURL SUPublicDSAKeyFile; do
    /usr/libexec/PlistBuddy -c "Delete :$k" "$PL" 2>/dev/null || true
done

# Cloud art is licensed for use inside the app only, so it never goes into the repository:
# it is packed from a folder next to it (or CLOUDS_ART=...) straight into the app
CLOUDS_ART=${CLOUDS_ART:-../clouds-art}
if [ -d "$CLOUDS_ART" ]; then
    echo "==> Clouds from $CLOUDS_ART"
    "$APP/Contents/MacOS/MTMR" --pack-clouds "$CLOUDS_ART" "$RES/Clouds.pack"
else
    echo "==> No cloud art ($CLOUDS_ART): the clouds mode will only show your own"
fi

echo "==> Signing (ad-hoc)"
# Requirement by bundle id instead of the default cdhash: macOS privacy permissions
# (Accessibility for the keyboard) stay granted after every rebuild.
codesign --force --sign - -r='designated => identifier "local.MTMR"' "$APP"

echo "Done: $APP ($ARCH)"
