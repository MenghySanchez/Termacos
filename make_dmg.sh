#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Termacos SSH"
VERSION="$(cat VERSION)"
DMG_VOLNAME="${APP_NAME}"
DMG_PATH="dist/TermacosSSH-${VERSION}.dmg"
STAGING_DIR="dist/.dmg-staging"
INSTALLERS_DIR="Installers"

echo "Building and packaging the app..."
./package_app.sh

echo "Staging DMG contents..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "dist/${APP_NAME}.app" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating ${DMG_PATH}..."
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${DMG_VOLNAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo "Archiving into ${INSTALLERS_DIR}/..."
mkdir -p "${INSTALLERS_DIR}"
cp "${DMG_PATH}" "${INSTALLERS_DIR}/$(basename "${DMG_PATH}")"

echo "Done: ${DMG_PATH}"
echo "Archived: ${INSTALLERS_DIR}/$(basename "${DMG_PATH}")"
echo ""
echo "All installer versions:"
ls -1 "${INSTALLERS_DIR}"
