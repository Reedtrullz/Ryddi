#!/bin/bash
set -euo pipefail

VERSION="${1:?usage: Scripts/build-installer.sh VERSION}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use semantic form X.Y.Z" >&2
    exit 2
fi
BUILD_DIR=".build/release"
APP_NAME="Ryddi.app"
PKG_NAME="Ryddi-v${VERSION}.pkg"
DIST_DIR="dist"

APP_SIGN_ID="${APP_SIGNING_IDENTITY:?APP_SIGNING_IDENTITY is required}"
INSTALLER_SIGN_ID="${INSTALLER_SIGNING_IDENTITY:?INSTALLER_SIGNING_IDENTITY is required}"
NOTARY_KEY="${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}"
NOTARY_ISSUER="${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"
[[ -f "$NOTARY_KEY_PATH" ]] || { echo "NOTARY_KEY_PATH does not exist" >&2; exit 2; }
SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Assets/Info.plist)"
SOURCE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Assets/Info.plist)"
[[ "$SOURCE_VERSION" == "$VERSION" ]] || { echo "Assets/Info.plist version is ${SOURCE_VERSION}, expected ${VERSION}" >&2; exit 2; }
[[ "$SOURCE_BUILD" =~ ^[0-9]+$ ]] || { echo "Assets/Info.plist build must be numeric" >&2; exit 2; }

echo "=== Building Ryddi v${VERSION} ==="

swift build -c release --scratch-path .build

BUILD_STAGE="${DIST_DIR}/build-staging"
rm -rf "${BUILD_STAGE}"
mkdir -p "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/MacOS"
mkdir -p "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/Resources"

cp "${BUILD_DIR}/RyddiApp" "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/MacOS/"
chmod +x "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/MacOS/RyddiApp"

cp Assets/Info.plist "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/"
cp Assets/Ryddi.icns "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/Resources/"
cp -R "${BUILD_DIR}/Ryddi_ReclaimerCore.bundle" "${BUILD_STAGE}/Applications/${APP_NAME}/Contents/Resources/"

xattr -cr "${BUILD_STAGE}/Applications/${APP_NAME}"
find "${BUILD_STAGE}" -name '._*' -delete

echo "=== Signing .app bundle ==="
codesign --force --sign "$APP_SIGN_ID" \
    --options runtime \
    --timestamp \
    "${BUILD_STAGE}/Applications/${APP_NAME}"
codesign --verify --deep --strict --verbose=2 "${BUILD_STAGE}/Applications/${APP_NAME}"

echo "=== Building .pkg installer ==="

pkgbuild \
    --root "${BUILD_STAGE}" \
    --component-plist Scripts/component.plist \
    --identifier com.reedtrullz.ryddi \
    --version "${VERSION}" \
    --install-location "/" \
    "${DIST_DIR}/RyddiComponent.pkg"

productbuild \
    --distribution Scripts/Distribution.xml \
    --package-path "${DIST_DIR}" \
    --version "${VERSION}" \
    "${DIST_DIR}/${PKG_NAME}"

rm -rf "${BUILD_STAGE}" "${DIST_DIR}/RyddiComponent.pkg"

echo "=== Signing .pkg ==="
productsign --sign "$INSTALLER_SIGN_ID" \
    "${DIST_DIR}/${PKG_NAME}" \
    "${DIST_DIR}/${PKG_NAME}.signed"
mv "${DIST_DIR}/${PKG_NAME}.signed" "${DIST_DIR}/${PKG_NAME}"
pkgutil --check-signature "${DIST_DIR}/${PKG_NAME}" | grep -q "Developer ID Installer"

echo "=== Notarizing .pkg ==="
xcrun notarytool submit "${DIST_DIR}/${PKG_NAME}" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY" \
    --issuer "$NOTARY_ISSUER" \
    --wait

echo "=== Stapling and Gatekeeper verification ==="
xcrun stapler staple "${DIST_DIR}/${PKG_NAME}"
xcrun stapler validate "${DIST_DIR}/${PKG_NAME}"
spctl --assess --type install --verbose=2 "${DIST_DIR}/${PKG_NAME}"

echo "=== Generating checksum ==="
shasum -a 256 "${DIST_DIR}/${PKG_NAME}" > "${DIST_DIR}/${PKG_NAME}.sha256"

echo "=== Done ==="
echo "Installer: ${DIST_DIR}/${PKG_NAME}"
echo "Checksum:  ${DIST_DIR}/${PKG_NAME}.sha256"
