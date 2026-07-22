#!/bin/bash
set -euo pipefail

VERSION="${1:?usage: Scripts/build-release-archive.sh VERSION}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use semantic form X.Y.Z" >&2
    exit 2
fi

APP_SIGN_ID="${APP_SIGNING_IDENTITY:?APP_SIGNING_IDENTITY is required}"
NOTARY_PROFILE_NAME="${NOTARY_PROFILE:?NOTARY_PROFILE is required}"
BUILD_DIR=".build/release"
DIST_DIR="dist"
STAGE_DIR="${DIST_DIR}/archive-staging"
APP_PATH="${STAGE_DIR}/Ryddi.app"
SUBMISSION_ZIP="${DIST_DIR}/Ryddi-v${VERSION}-submission.zip"
RELEASE_ZIP="${DIST_DIR}/Ryddi-v${VERSION}.zip"
RELEASE_BASENAME="$(basename "$RELEASE_ZIP")"
NOTARY_RESULT="${DIST_DIR}/Ryddi-v${VERSION}-notary.json"
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Assets/Info.plist)"
SOURCE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Assets/Info.plist)"
[[ "$SOURCE_VERSION" == "$VERSION" ]] || { echo "Assets/Info.plist version is ${SOURCE_VERSION}, expected ${VERSION}" >&2; exit 2; }
[[ "$SOURCE_BUILD" =~ ^[0-9]+$ ]] || { echo "Assets/Info.plist build must be numeric" >&2; exit 2; }
RELEASE_COMPLETE=0

cleanup() {
    rm -rf "$STAGE_DIR" "$SUBMISSION_ZIP"
    if [[ "$RELEASE_COMPLETE" -ne 1 ]]; then
        rm -f "$RELEASE_ZIP" "$NOTARY_RESULT" "${RELEASE_ZIP}.sha256"
    fi
}
trap cleanup EXIT

swift build -c release --scratch-path .build

rm -rf "$STAGE_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/RyddiApp" "$APP_PATH/Contents/MacOS/"
chmod +x "$APP_PATH/Contents/MacOS/RyddiApp"
cp Assets/Info.plist "$APP_PATH/Contents/"
cp Assets/Ryddi.icns "$APP_PATH/Contents/Resources/"
cp -R "$BUILD_DIR/Ryddi_ReclaimerCore.bundle" "$APP_PATH/Contents/Resources/"

xattr -cr "$APP_PATH"
find "$APP_PATH" -name '._*' -delete

codesign --force --sign "$APP_SIGN_ID" --options runtime --timestamp "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$SUBMISSION_ZIP" "$RELEASE_ZIP" "$NOTARY_RESULT" "${RELEASE_ZIP}.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
    --keychain-profile "$NOTARY_PROFILE_NAME" \
    --wait \
    --output-format json > "$NOTARY_RESULT"
/usr/bin/python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); assert data.get("status") == "Accepted", data' "$NOTARY_RESULT"

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$RELEASE_ZIP"
(
    cd "$DIST_DIR"
    shasum -a 256 "$RELEASE_BASENAME" > "${RELEASE_BASENAME}.sha256"
)
RELEASE_COMPLETE=1

echo "Archive: ${RELEASE_ZIP}"
echo "Checksum: ${RELEASE_ZIP}.sha256"
echo "Notary result: ${NOTARY_RESULT}"
