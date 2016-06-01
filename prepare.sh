#!/usr/bin/env bash

set -o errexit

readonly RELEASE="5.1"
readonly APP_NAME="Squeak-${RELEASE}-All-in-One.app"

readonly BUILD_DIR="${TRAVIS_BUILD_DIR}/build"
readonly SCRIPTS_DIR="${TRAVIS_BUILD_DIR}/scripts"
readonly TEMPLATE_DIR="${TRAVIS_BUILD_DIR}/template"
readonly TMP_DIR="${TRAVIS_BUILD_DIR}/tmp"
readonly APP_DIR="${BUILD_DIR}/${APP_NAME}"
readonly CONTENTS_DIR="${APP_DIR}/Contents"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"

readonly IMAGE_URL="http://build.squeak.org/job/Trunk/default/\
lastSuccessfulBuild/artifact/target/TrunkImage.zip"
readonly SOURCES_URL="http://ftp.squeak.org/sources_files/SqueakV50.sources.gz"

readonly VM_BASE="http://www.mirandabanda.org/files/Cog/VM/latest/"
readonly VM_VERSION="16.21.3732"
readonly VM_ARM="cogspurlinuxhtARM-${VM_VERSION}.tgz"
readonly VM_LIN="cogspurlinuxht-${VM_VERSION}.tgz"
readonly VM_OSX="CogSpur.app-${VM_VERSION}.tgz"
readonly VM_WIN="cogspurwin-${VM_VERSION}.zip"

readonly VM_ARM_TARGET="${CONTENTS_DIR}/Linux-ARM"
readonly VM_LIN_TARGET="${CONTENTS_DIR}/Linux-i686"
readonly VM_OSX_TARGET="${CONTENTS_DIR}/MacOS"
readonly VM_WIN_TARGET="${CONTENTS_DIR}/Win32"

readonly TARGET_TARGZ="${TRAVIS_BUILD_DIR}/${APP_NAME}.tar.gz"
readonly TARGET_ZIP="${TRAVIS_BUILD_DIR}/${APP_NAME}.zip"
readonly TARGET_URL="https://www.hpi.uni-potsdam.de/hirschfeld/artefacts/squeak/"

echo "Make build and tmp directories..."
mkdir "${BUILD_DIR}" "${TMP_DIR}"

echo "Downloading and extracting OS X VM..."
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_OSX}" "${VM_BASE}/${VM_OSX}"
tar xzf "${TMP_DIR}/${VM_OSX}" -C "${TMP_DIR}/"
mv "${TMP_DIR}/CogSpur.app/CogSpur.app" "${APP_DIR}"

echo "Downloading and extracting Linux and Windows VMs..."
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_ARM}" "${VM_BASE}/${VM_ARM}"
tar xzf "${TMP_DIR}/${VM_ARM}" -C "${TMP_DIR}/"
mv "${TMP_DIR}/cogspurlinuxhtARM" "${VM_ARM_TARGET}"
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_LIN}" "${VM_BASE}/${VM_LIN}"
tar xzf "${TMP_DIR}/${VM_LIN}" -C "${TMP_DIR}/"
mv "${TMP_DIR}/cogspurlinuxht" "${VM_LIN_TARGET}"
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_WIN}" "${VM_BASE}/${VM_WIN}"
unzip -q "${TMP_DIR}/${VM_WIN}" -d "${TMP_DIR}/"
mv "${TMP_DIR}/cogspurwin" "${VM_WIN_TARGET}"

echo "Setting permissions..."
chmod +x "${VM_ARM_TARGET}/squeak" "${VM_LIN_TARGET}/squeak" "${VM_OSX_TARGET}/Squeak" "${VM_WIN_TARGET}/Squeak.exe"

echo "Adding start scripts..."
echo ".\${APP_NAME}\Contents\Win32\Squeak.exe" > "${BUILD_DIR}/squeak.bat"
echo "./${APP_NAME}/Contents/squeak.sh" > "${BUILD_DIR}/squeak.sh"

echo "Merging template..."
mv "${TEMPLATE_DIR}/Squeak.app/Contents/Library" "${CONTENTS_DIR}/"
mv "${TEMPLATE_DIR}/Squeak.app/Contents/Info.plist" "${CONTENTS_DIR}/"
mv "${TEMPLATE_DIR}/Squeak.app/Contents/squeak.sh" "${CONTENTS_DIR}/"
mv "${TEMPLATE_DIR}/Squeak.app/Contents/Win32/Squeak.ini" "${VM_WIN_TARGET}/"

echo "Downloading and extracting base image..."
curl -f -s --retry 3 -o "${TMP_DIR}/base.zip" "${IMAGE_URL}"
unzip -q "${TMP_DIR}/base.zip" -d "${TMP_DIR}/"
mv "${TMP_DIR}/"*.image "${TMP_DIR}/Squeak.image"
mv "${TMP_DIR}/"*.changes "${TMP_DIR}/Squeak.changes"

mv "${TMP_DIR}/SpurTrunkImage.image" "${RESOURCES_DIR}/"
mv "${TMP_DIR}/SpurTrunkImage.changes" "${RESOURCES_DIR}/"

echo "Downloading and extracting sources file..."
curl -f -s --retry 3 -o "${TMP_DIR}/sources.gz" "${SOURCES_URL}"
gunzip -c "${TMP_DIR}/sources.gz" > "${RESOURCES_DIR}/SqueakV50.sources"

echo "Retrieving image information and move image into bundle..."
IMAGE_NAME=$("${VM_OSX_TARGET}/Squeak" -headless "${TMP_DIR}/Squeak.image" "${SCRIPTS_DIR}/get_version.st")
mv "${TMP_DIR}/Squeak.image" "${RESOURCES_DIR}/${IMAGE_NAME}.image"
mv "${TMP_DIR}/Squeak.changes" "${RESOURCES_DIR}/${IMAGE_NAME}.changes"

echo "Updating Info.plist..."
sed -i ".bak" "s/%CFBundleGetInfoString%/${IMAGE_NAME}, SpurVM 5.0-3397/g" "${CONTENTS_DIR}/Info.plist"
sed -i ".bak" "s/%VERSION%/${RELEASE}/g" "${CONTENTS_DIR}/Info.plist"
sed -i ".bak" "s/%SqueakImageName%/${IMAGE_NAME}.image/g" "${CONTENTS_DIR}/Info.plist"
rm -f "${CONTENTS_DIR}/Info.plist.bak"

echo "Updating squeak.sh..."
sed -i ".bak" "s/%SqueakImageName%/${IMAGE_NAME}.image/g" "${CONTENTS_DIR}/squeak.sh"
rm -f "${CONTENTS_DIR}/squeak.bak"

echo "Updating Squeak.ini..."
sed -i ".bak" "s/%VERSION%/${RELEASE}.image/g" "${VM_WIN_TARGET}/Squeak.ini"
sed -i ".bak" "s/%SqueakImageName%/${IMAGE_NAME}.image/g" "${VM_WIN_TARGET}/Squeak.ini"
rm -f "${VM_WIN_TARGET}/Squeak.ini"

echo "Signing app bundle..."
unzip -q ./certs/dist.zip -d ./certs
security create-keychain -p travis osx-build.keychain
security default-keychain -s osx-build.keychain
security unlock-keychain -p travis osx-build.keychain
security import ./certs/dist.cer -k ~/Library/Keychains/osx-build.keychain -T /usr/bin/codesign
security import ./certs/dist.p12 -k ~/Library/Keychains/osx-build.keychain -P "${CERT_PASSWORD}" -T /usr/bin/codesign
codesign -s "${SIGN_IDENTITY}" --force --deep --verbose "${APP_DIR}"
security delete-keychain osx-build.keychain

echo "Compressing bundle..."
pushd "${BUILD_DIR}" > /dev/null
tar czf "${TARGET_TARGZ}" "./"
zip -q -r "${TARGET_ZIP}" "./"
popd > /dev/null

echo "Uploading files..."
curl -T "${TARGET_TARGZ}" -u "${DEPLOY_CREDENTIALS}" "${TARGET_URL}"
curl -T "${TARGET_ZIP}" -u "${DEPLOY_CREDENTIALS}" "${TARGET_URL}"

echo "Done!"
