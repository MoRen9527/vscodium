#!/usr/bin/env bash

set -e

cd "$( dirname "${BASH_SOURCE[0]}" )"

WIN_SDK_MAJOR_VERSION="10"
WIN_SDK_FULL_VERSION="10.0.22621.0"
SETUP_RELEASE_DIR="./releasedir"
OUTPUT_BASE_FILENAME="TriCade-${VSCODE_ARCH}-${RELEASE_VERSION}"

if [[ "${VSCODE_ARCH}" == "ia32" ]]; then
   PLATFORM="x86"
else
   PLATFORM="${VSCODE_ARCH}"
fi

PROGRAM_FILES_86=$( env | sed -n 's/^ProgramFiles(x86)=//p' )
LANGIDS="1033"

BuildSetupTranslationTransform() {
	local CULTURE=${1}
	local LANGID=${2}
	LANGIDS="${LANGIDS},${LANGID}"
	echo "Building setup translation for ${CULTURE} (LangID ${LANGID})..."
	./bin/light.exe vscodium.wixobj "Files-${OUTPUT_BASE_FILENAME}.wixobj" -ext WixUIExtension -ext WixUtilExtension -ext WixNetFxExtension -spdb -cc "${TEMP}/vscodium-cab-cache/${PLATFORM}" -reusecab -out "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.msi" -loc "i18n/vscodium.${CULTURE}.wxl" -cultures:"${CULTURE}" -sice:ICE60 -sice:ICE69
	echo "  WiLangId..."
	cscript "${PROGRAM_FILES_86}/Windows Kits/${WIN_SDK_MAJOR_VERSION}/bin/${WIN_SDK_FULL_VERSION}/${PLATFORM}/WiLangId.vbs" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.msi" Product "${LANGID}"
	echo "  msitran..."
	"${PROGRAM_FILES_86}/Windows Kits/${WIN_SDK_MAJOR_VERSION}/bin/${WIN_SDK_FULL_VERSION}/x86/msitran" -g "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.msi" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.msi" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.mst"
	echo "  wisubstg..."
	cscript "${PROGRAM_FILES_86}/Windows Kits/${WIN_SDK_MAJOR_VERSION}/bin/${WIN_SDK_FULL_VERSION}/${PLATFORM}/wisubstg.vbs" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.msi" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.mst" "${LANGID}"
	cscript "${PROGRAM_FILES_86}/Windows Kits/${WIN_SDK_MAJOR_VERSION}/bin/${WIN_SDK_FULL_VERSION}/${PLATFORM}/wisubstg.vbs" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.msi"
	rm -f "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.msi"
	rm -f "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.${CULTURE}.mst"
	echo "  Done: ${CULTURE}"
}

echo "=== Running language transforms ==="
BuildSetupTranslationTransform de-de 1031
BuildSetupTranslationTransform es-es 3082
BuildSetupTranslationTransform fr-fr 1036
BuildSetupTranslationTransform it-it 1040
BuildSetupTranslationTransform ko-kr 1042
BuildSetupTranslationTransform ru-ru 1049
BuildSetupTranslationTransform zh-cn 2052
BuildSetupTranslationTransform zh-tw 1028

echo "=== Final WiLangId ==="
cscript "${PROGRAM_FILES_86}/Windows Kits/${WIN_SDK_MAJOR_VERSION}/bin/${WIN_SDK_FULL_VERSION}/${PLATFORM}/WiLangId.vbs" "${SETUP_RELEASE_DIR}/${OUTPUT_BASE_FILENAME}.msi" Package "${LANGIDS}"

echo "=== Cleanup ==="
rm -rf "${TEMP}/vscodium-cab-cache"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wxs"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wixobj"
rm -f "vscodium.wixobj"

echo "=== All language transforms complete ==="
