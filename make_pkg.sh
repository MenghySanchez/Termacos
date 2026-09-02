#!/bin/bash
set -euo pipefail

export COPYFILE_DISABLE=1

cd "$(dirname "$0")"

APP_NAME="Termacos SSH"
BUNDLE_ID="com.menghysanchez.termacos-ssh"
PKG_ID="${BUNDLE_ID}.installer"
VERSION="$(cat VERSION)"
ROOT_DIR="dist/.pkg-root"
PKG_PATH="dist/TermacosSSH-${VERSION}.pkg"
INSTALLERS_DIR="Installers"

echo "Building app for PKG installer..."
./package_app.sh

echo "Preparing PKG root..."
rm -rf "${ROOT_DIR}"
mkdir -p "${ROOT_DIR}/Applications"
/usr/bin/ditto --noextattr --norsrc "dist/${APP_NAME}.app" "${ROOT_DIR}/Applications/${APP_NAME}.app"
xattr -cr "${ROOT_DIR}"

echo "Creating ${PKG_PATH}..."
rm -f "${PKG_PATH}"
pkgbuild \
    --root "${ROOT_DIR}" \
    --scripts "InstallerScripts" \
    --identifier "${PKG_ID}" \
    --version "${VERSION}" \
    --install-location "/" \
    "${PKG_PATH}"

rm -rf "${ROOT_DIR}"

echo "Archiving into ${INSTALLERS_DIR}/..."
mkdir -p "${INSTALLERS_DIR}"
cp "${PKG_PATH}" "${INSTALLERS_DIR}/$(basename "${PKG_PATH}")"

echo "Done: ${PKG_PATH}"
echo "Archived: ${INSTALLERS_DIR}/$(basename "${PKG_PATH}")"
