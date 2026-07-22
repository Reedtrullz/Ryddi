#!/bin/bash
set -euo pipefail

VERSION="${1:-0.8.0}"
BUILD_DIR=".build/release"
APP_NAME="Ryddi.app"
PKG_NAME="Ryddi-v${VERSION}.pkg"
DIST_DIR="dist"

echo "=== Building Ryddi v${VERSION} ==="

swift build -c release --scratch-path .build

rm -rf "${DIST_DIR}/${APP_NAME}"
mkdir -p "${DIST_DIR}/${APP_NAME}/Contents/MacOS"
mkdir -p "${DIST_DIR}/${APP_NAME}/Contents/Resources"

cp "${BUILD_DIR}/RyddiApp" "${DIST_DIR}/${APP_NAME}/Contents/MacOS/"
chmod +x "${DIST_DIR}/${APP_NAME}/Contents/MacOS/RyddiApp"

cp Assets/Info.plist "${DIST_DIR}/${APP_NAME}/Contents/"
cp Assets/Ryddi.icns "${DIST_DIR}/${APP_NAME}/Contents/Resources/"

xattr -cr "${DIST_DIR}/${APP_NAME}"

echo "=== Building .pkg installer ==="

STAGE="${DIST_DIR}/pkg-root"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/Applications"
cp -R "${DIST_DIR}/${APP_NAME}" "${STAGE}/Applications/"

pkgbuild \
    --root "${STAGE}" \
    --identifier com.reedtrullz.ryddi \
    --version "${VERSION}" \
    --install-location "/" \
    "${DIST_DIR}/${PKG_NAME}"

rm -rf "${STAGE}"
echo "=== Done ==="
echo "Installer: ${DIST_DIR}/${PKG_NAME}"
