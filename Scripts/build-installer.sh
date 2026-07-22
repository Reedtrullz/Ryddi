#!/bin/bash
set -euo pipefail

VERSION="${1:-0.8.1}"
BUILD_DIR=".build/release"
APP_NAME="Ryddi.app"
PKG_NAME="Ryddi-v${VERSION}.pkg"
DIST_DIR="dist"

SIGN_ID="${SIGNING_IDENTITY:-}"
NOTARY_KEY="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${NOTARY_ISSUER_ID:-}"

echo "=== Building Ryddi v${VERSION} ==="

swift build -c release --scratch-path .build

BUILD_STAGE="${DIST_DIR}/build-staging"
rm -rf "${BUILD_STAGE}"
mkdir -p "${BUILD_STAGE}/${APP_NAME}/Contents/MacOS"
mkdir -p "${BUILD_STAGE}/${APP_NAME}/Contents/Resources"

cp "${BUILD_DIR}/RyddiApp" "${BUILD_STAGE}/${APP_NAME}/Contents/MacOS/"
chmod +x "${BUILD_STAGE}/${APP_NAME}/Contents/MacOS/RyddiApp"

cp Assets/Info.plist "${BUILD_STAGE}/${APP_NAME}/Contents/"
cp Assets/Ryddi.icns "${BUILD_STAGE}/${APP_NAME}/Contents/Resources/"

xattr -cr "${BUILD_STAGE}/${APP_NAME}"

if [[ -n "$SIGN_ID" ]]; then
    echo "=== Signing .app bundle ==="
    codesign --force --sign "$SIGN_ID" \
        --entitlements Assets/Ryddi.entitlements \
        --options runtime \
        --timestamp \
        "${BUILD_STAGE}/${APP_NAME}"
else
    echo "⚠️  No SIGNING_IDENTITY set. Skipping code signing."
    echo "   Set with: export SIGNING_IDENTITY='Developer ID Application: Your Name'"
fi

echo "=== Building .pkg installer ==="

pkgbuild \
    --component "${BUILD_STAGE}/${APP_NAME}" \
    --identifier com.reedtrullz.ryddi \
    --version "${VERSION}" \
    --install-location "/Applications" \
    "${DIST_DIR}/RyddiComponent.pkg"

productbuild \
    --distribution Scripts/Distribution.xml \
    --package-path "${DIST_DIR}" \
    --version "${VERSION}" \
    "${DIST_DIR}/${PKG_NAME}"

rm -rf "${BUILD_STAGE}" "${DIST_DIR}/RyddiComponent.pkg"

if [[ -n "$SIGN_ID" ]]; then
    echo "=== Signing .pkg ==="
    productsign --sign "$SIGN_ID" \
        "${DIST_DIR}/${PKG_NAME}" \
        "${DIST_DIR}/${PKG_NAME}.signed"
    mv "${DIST_DIR}/${PKG_NAME}.signed" "${DIST_DIR}/${PKG_NAME}"
fi

if [[ -n "$NOTARY_KEY" && -n "$NOTARY_ISSUER" ]]; then
    echo "=== Notarizing .pkg ==="
    xcrun notarytool submit "${DIST_DIR}/${PKG_NAME}" \
        --key-id "$NOTARY_KEY" \
        --issuer "$NOTARY_ISSUER" \
        --wait
    
    echo "=== Stapling notarization ==="
    xcrun stapler staple "${DIST_DIR}/${PKG_NAME}"
else
    echo "⚠️  No NOTARY_KEY_ID/NOTARY_ISSUER_ID set. Skipping notarization."
    echo "   Set with: export NOTARY_KEY_ID='your-key-id'"
    echo "   export NOTARY_ISSUER_ID='your-issuer-id'"
fi

echo "=== Generating checksum ==="
shasum -a 256 "${DIST_DIR}/${PKG_NAME}" > "${DIST_DIR}/${PKG_NAME}.sha256"

echo "=== Done ==="
echo "Installer: ${DIST_DIR}/${PKG_NAME}"
echo "Checksum:  ${DIST_DIR}/${PKG_NAME}.sha256"
