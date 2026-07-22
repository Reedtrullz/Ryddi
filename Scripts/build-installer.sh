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

echo "=== Building .pkg installer ==="
pkgbuild \
    --root "${DIST_DIR}/${APP_NAME}" \
    --identifier com.reedtrullz.ryddi \
    --version "${VERSION}" \
    --install-location "/Applications/${APP_NAME}" \
    "${DIST_DIR}/${PKG_NAME}"

echo "=== Done ==="
echo "Installer: ${DIST_DIR}/${PKG_NAME}"
