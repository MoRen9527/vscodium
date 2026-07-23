#!/usr/bin/env bash
#
# build-base.sh �?TriCade Base MSI (vscodium core only, no TriMetaverse components).
#
# Usage:  VSCODE_ARCH=x64 RELEASE_VERSION=1.126.04524 WIX=/path/to/wix/ ./build-base.sh
#
# Key differences from the legacy monolithic build.sh:
#   - BINARY_DIR = C:\Temp\tricade-base (vscodium only, no TriMetaverse overlay)
#   - PRODUCT_NAME = "TriCade Base"
#   - PRODUCT_CODE = "TriCadeBase"
#   - Keeps the same UpgradeCode for seamless upgrade from monolithic TriCade
#   - Keeps all 9 language translations
#   - Output: TriCade-Base-x64-{version}.msi

set -ex

CALLER_DIR=$( pwd )

cd "$( dirname "${BASH_SOURCE[0]}" )"

WIN_SDK_MAJOR_VERSION="10"
WIN_SDK_FULL_VERSION="10.0.22621.0"

# ── Base-specific product identity ──────────────────────────────────────────
PRODUCT_NAME="TriCade Base"
PRODUCT_CODE="TriCadeBase"
# Same UpgradeCode as legacy TriCade �?allows Base to replace the monolithic MSI
PRODUCT_UPGRADE_CODE="{3E4650C5-DA37-434D-9FD7-574B6F798BE0}"
# AppName must match legacy TriCade for registry compatibility with Bundle MSI
APP_NAME="TriCade"
ICON_DIR="..\\..\\..\\src\\stable\\resources\\win32"
SETUP_RESOURCES_DIR=".\\resources\\stable"

PRODUCT_ID=$( powershell.exe -command "[guid]::NewGuid().ToString().ToUpper()" )
PRODUCT_ID="${PRODUCT_ID%%[[:cntrl:]]}"

CULTURE="en-us"
LANGIDS="1033"

SETUP_RELEASE_DIR=".\\releasedir"

# ── BINARY_DIR: vscodium core only (no TriMetaverse overlay) ────────────────
# NOTE: WiX heat.exe cannot enumerate OneDrive-synced directories.
# Copy VSCode-win32-x64 to C:\Temp\tricade-base before building.
BINARY_DIR="C:\\Temp\\tricade-base"
LICENSE_DIR="..\\..\\..\\vscode"
PROGRAM_FILES_86=$( env | sed -n 's/^ProgramFiles(x86)=//p' )

OUTPUT_BASE_FILENAME="TriCade-Base-${VSCODE_ARCH}-${RELEASE_VERSION}"

if [[ "${VSCODE_ARCH}" == "ia32" ]]; then
   export PLATFORM="x86"
else
   export PLATFORM="${VSCODE_ARCH}"
fi

# ── Patch i18n files temporarily for "TriCade Base" product name ────────────
# The i18n/*.wxl files are shared with the legacy build.sh (which uses "TriCade").
# We sed in-place before building and restore after to avoid permanently forking.
echo "Patching i18n ProductName: TriCade -> TriCade Base"
find i18n -name '*.wxl' -print0 | xargs -0 sed -i 's|<String Id="ProductName">TriCade</String>|<String Id="ProductName">TriCade Base</String>|g'
# Ensure i18n restore on script exit (even if build fails)
trap 'find i18n -name "*.wxl" -print0 | xargs -0 sed -i "s|<String Id=\"ProductName\">TriCade Base</String>|<String Id=\"ProductName\">TriCade</String>|g"' EXIT

# Also patch the non-templated vscodium-variables.wxi for UpgradeCode
# (The wxi has a hardcoded value; sed it in case it differs from above.)
sed -i "s|@@PRODUCT_UPGRADE_CODE@@|${PRODUCT_UPGRADE_CODE}|g" .\\includes\\vscodium-variables.wxi

# vscodium.xsl may reference @@PRODUCT_NAME@@ �?sed it for Base
sed -i "s|@@PRODUCT_NAME@@|${PRODUCT_NAME}|g" .\\vscodium.xsl

# ── Translation transform helper (same as legacy) ───────────────────────────
BuildSetupTranslationTransform() {
	local CULTURE=${1}
	local LANGID=${2}

	LANGIDS="${LANGIDS},${LANGID}"

	echo "Building setup translation for culture \"${CULTURE}\" with LangID \"${LANGID}\"..."

	"${WIX}bin/light.exe" vscodium.wixobj "Files-${OUTPUT_BASE_FILENAME}.wixobj" \
		-ext WixUIExtension -ext WixUtilExtension -ext WixNetFxExtension \
		-spdb -cc "${TEMP}\\vscodium-cab-cache\\${PLATFORM}" -reusecab \
		-out "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.msi" \
		-loc "i18n\\vscodium.${CULTURE}.wxl" \
		-cultures:"${CULTURE}" \
		-sice:ICE60 -sice:ICE69

	cscript "${PROGRAM_FILES_86}\\Windows Kits\\${WIN_SDK_MAJOR_VERSION}\\bin\\${WIN_SDK_FULL_VERSION}\\${PLATFORM}\\WiLangId.vbs" \
		"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.msi" Product "${LANGID}"

	"${PROGRAM_FILES_86}\\Windows Kits\\${WIN_SDK_MAJOR_VERSION}\\bin\\${WIN_SDK_FULL_VERSION}\\x86\\msitran" \
		-g "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" \
		"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.msi" \
		"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.mst"

	cscript "${PROGRAM_FILES_86}\\Windows Kits\\${WIN_SDK_MAJOR_VERSION}\\bin\\${WIN_SDK_FULL_VERSION}\\${PLATFORM}\\wisubstg.vbs" \
		"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" \
		"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.mst" "${LANGID}"

	cscript "${PROGRAM_FILES_86}\\Windows Kits\\${WIN_SDK_MAJOR_VERSION}\\bin\\${WIN_SDK_FULL_VERSION}\\${PLATFORM}\\wisubstg.vbs" \
		"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi"

	rm -f "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.msi"
	rm -f "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.${CULTURE}.mst"
}

# ── Build ───────────────────────────────────────────────────────────────────

# Step 1: Harvest files from BINARY_DIR (vscodium core only)
echo "=== Harvesting files from ${BINARY_DIR} ==="
"${WIX}bin/heat.exe" dir "${BINARY_DIR}" \
	-out "Files-${OUTPUT_BASE_FILENAME}.wxs" \
	-t vscodium.xsl \
	-gg -sfrag -scom -sreg -srd -ke \
	-cg "AppFiles" \
	-var var.ManufacturerName \
	-var var.AppName \
	-var var.AppCodeName \
	-var var.ProductVersion \
	-var var.IconDir \
	-var var.LicenseDir \
	-var var.BinaryDir \
	-dr APPLICATIONFOLDER \
	-platform "${PLATFORM}"

# Step 2: Compile to .wixobj
echo "=== Compiling ==="
"${WIX}bin/candle.exe" -arch "${PLATFORM}" \
	vscodium.wxs \
	"Files-${OUTPUT_BASE_FILENAME}.wxs" \
	-ext WixUIExtension -ext WixUtilExtension -ext WixNetFxExtension \
	-dManufacturerName="TriMetaverse" \
	-dAppCodeName="${PRODUCT_CODE}" \
	-dAppName="${APP_NAME}" \
	-dProductVersion="${RELEASE_VERSION%-insider}" \
	-dProductId="${PRODUCT_ID}" \
	-dBinaryDir="${BINARY_DIR}" \
	-dIconDir="${ICON_DIR}" \
	-dLicenseDir="${LICENSE_DIR}" \
	-dSetupResourcesDir="${SETUP_RESOURCES_DIR}" \
	-dCulture="${CULTURE}"

# Step 3: Link en-us base MSI
echo "=== Linking en-us ==="
"${WIX}bin/light.exe" vscodium.wixobj "Files-${OUTPUT_BASE_FILENAME}.wixobj" \
	-ext WixUIExtension -ext WixUtilExtension -ext WixNetFxExtension \
	-spdb -cc "${TEMP}\\vscodium-cab-cache\\${PLATFORM}" \
	-out "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" \
	-loc "i18n\\vscodium.${CULTURE}.wxl" \
	-cultures:"${CULTURE}" \
	-sice:ICE60 -sice:ICE69

# Step 4: Build and embed all 8 additional language transforms
BuildSetupTranslationTransform de-de 1031
BuildSetupTranslationTransform es-es 3082
BuildSetupTranslationTransform fr-fr 1036
BuildSetupTranslationTransform it-it 1040
# WixUI_Advanced bug: https://github.com/wixtoolset/issues/issues/5909
# BuildSetupTranslationTransform ja-jp 1041
BuildSetupTranslationTransform ko-kr 1042
BuildSetupTranslationTransform ru-ru 1049
BuildSetupTranslationTransform zh-cn 2052
BuildSetupTranslationTransform zh-tw 1028

# Step 5: Stamp all language IDs into the MSI Package attribute
cscript "${PROGRAM_FILES_86}\\Windows Kits\\${WIN_SDK_MAJOR_VERSION}\\bin\\${WIN_SDK_FULL_VERSION}\\${PLATFORM}\\WiLangId.vbs" \
	"${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" Package "${LANGIDS}"

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf "${TEMP}\\vscodium-cab-cache"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wxs"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wixobj"
rm -f "vscodium.wixobj"

cd "${CALLER_DIR}"

echo "=== TriCade Base MSI built: ${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi ==="
