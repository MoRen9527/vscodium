#!/usr/bin/env bash
#
# build-bundle.sh — TriCade Bundle MSI (TriMetaverse components only).
#
# Usage:  VSCODE_ARCH=x64 RELEASE_VERSION=1.126.04524 WIX=/path/to/wix/ ./build-bundle.sh
#
# This MSI overlays TriPilot + TriLC + TriCode onto an existing TriCade Base
# installation. It checks for the Base registry key before installing and
# uses the same %ProgramFiles%\TriCade\ directory.
#
# Prerequisites:
#   1. TriPilot built: D:\OneDrive\Code\ai\TriPilot\out\ + package.json
#   2. TriLC built:    D:\OneDrive\Code\ai\TriLC\dist\ + package.json
#   3. TriCode built:   D:\OneDrive\Code\ai\TriCode\dist\ + package.json (if available)
#
# The script constructs C:\Temp\tricade-bundle with the overlay structure,
# then builds a minimal WiX MSI (~5-30 MB, <1 min).

set -ex

CALLER_DIR=$( pwd )

cd "$( dirname "${BASH_SOURCE[0]}" )"

WIN_SDK_MAJOR_VERSION="10"
WIN_SDK_FULL_VERSION="10.0.22621.0"

# ── Bundle product identity ─────────────────────────────────────────────────
PRODUCT_NAME="TriCade Bundle"
PRODUCT_CODE="TriCadeBundle"
# Independent UpgradeCode — Bundle is a separate MSI product from Base
PRODUCT_UPGRADE_CODE="{8F7A2B1C-D3E4-5678-9ABC-DEF012345678}"

PRODUCT_ID=$( powershell.exe -command "[guid]::NewGuid().ToString().ToUpper()" )
PRODUCT_ID="${PRODUCT_ID%%[[:cntrl:]]}"

CULTURE="en-us"

SETUP_RELEASE_DIR=".\\releasedir"

# ── Source repositories (absolute paths) ────────────────────────────────────
TRIPILOT_DIR="D:\\OneDrive\\Code\\ai\\TriPilot"
TRILC_DIR="D:\\OneDrive\\Code\\ai\\TriLC"
TRICODE_DIR="D:\\OneDrive\\Code\\ai\\TriCode"
TRICOMPANY_SOURCE_DIR="D:\\OneDrive\\Code\\ai\\TriCompany\\.github\\source-agents"
TRIMC_AGENT_CORE_DIR="D:\\OneDrive\\Code\\ai\\TriMC\\packages\\agent-core"
TRIMODEL_DIR="D:\\OneDrive\\Code\\ai\\TriModel"

# ── BINARY_DIR: overlay structure mimicking the TriCade install tree ────────
# heat.exe crawls this and maps it under APPLICATIONFOLDER (i.e. %ProgramFiles%\TriCade\).
# Structure:
#   resources/
#     app/
#       extensions/
#         tripilot-chat/    ← TriPilot out/ + package.json
#       tools/
#         trilc/             ← TriLC dist/ + node_modules + runtime contracts
#         tricode/           ← TriCode dist/ + package.json
BINARY_DIR="C:\\Temp\\tricade-bundle"

if [[ "${VSCODE_ARCH}" == "ia32" ]]; then
   export PLATFORM="x86"
else
   export PLATFORM="${VSCODE_ARCH}"
fi

OUTPUT_BASE_FILENAME="TriCade-Bundle-${VSCODE_ARCH}-${RELEASE_VERSION}"

PROGRAM_FILES_86=$( env | sed -n 's/^ProgramFiles(x86)=//p' )

# ── Construct BINARY_DIR from component repos ───────────────────────────────
echo "=== Constructing overlay source at ${BINARY_DIR} ==="

# Wipe and recreate
rm -rf "${BINARY_DIR}"
mkdir -p "${BINARY_DIR}/resources/app/extensions/tripilot-chat"
mkdir -p "${BINARY_DIR}/resources/app/tools/trilc"
mkdir -p "${BINARY_DIR}/resources/app/tools/trilc/contracts"
mkdir -p "${BINARY_DIR}/resources/app/tools/tricode"

# --- TriPilot extension ---
echo "Collecting TriPilot extension..."
if [[ -d "${TRIPILOT_DIR}/out" ]]; then
	cp -r "${TRIPILOT_DIR}/out" "${BINARY_DIR}/resources/app/extensions/tripilot-chat/"
fi
if [[ -f "${TRIPILOT_DIR}/package.json" ]]; then
	cp "${TRIPILOT_DIR}/package.json" "${BINARY_DIR}/resources/app/extensions/tripilot-chat/"
fi
if [[ -d "${TRIPILOT_DIR}/media" ]]; then
	cp -r "${TRIPILOT_DIR}/media" "${BINARY_DIR}/resources/app/extensions/tripilot-chat/"
fi

# --- TriLC tools ---
echo "Collecting TriLC..."
if [[ -d "${TRILC_DIR}/dist" ]]; then
	cp -r "${TRILC_DIR}/dist" "${BINARY_DIR}/resources/app/tools/trilc/"
fi
TRILC_STAGE="${BINARY_DIR}/resources/app/tools/trilc"
npm install --prefix "${TRILC_STAGE}" \
	--omit=dev --install-links --ignore-scripts --no-save --package-lock=false \
	"file:${TRIMC_AGENT_CORE_DIR}" \
	"file:${TRIMODEL_DIR}" \
	"yaml@^2.9.0"
if [[ -f "${TRILC_DIR}/package.json" ]]; then
	cp "${TRILC_DIR}/package.json" "${TRILC_STAGE}/"
fi
(
	cd "${TRILC_STAGE}"
	node --input-type=module -e "await import('@trimetaverse/agent-core'); await import('trimodel'); await import('yaml');"
)

# Publish only contract-backed employee directories as isolated runtime input.
# This path is outside .github/agents and is never exposed to VS Code discovery.
contract_count=0
for contract in "${TRICOMPANY_SOURCE_DIR}"/*/*.contract.yaml; do
	if [[ ! -f "${contract}" ]]; then
		continue
	fi
	cp -r "$( dirname "${contract}" )" "${BINARY_DIR}/resources/app/tools/trilc/contracts/"
	contract_count=$(( contract_count + 1 ))
done
if [[ "${contract_count}" -eq 0 ]]; then
	echo "No TriCompany agent contracts found under ${TRICOMPANY_SOURCE_DIR}" >&2
	exit 1
fi
echo "Collected ${contract_count} TriCompany agent contracts."

# --- TriCode tools ---
echo "Collecting TriCode..."
if [[ -d "${TRICODE_DIR}/dist" ]]; then
	cp -r "${TRICODE_DIR}/dist" "${BINARY_DIR}/resources/app/tools/tricode/"
fi
if [[ -f "${TRICODE_DIR}/package.json" ]]; then
	cp "${TRICODE_DIR}/package.json" "${BINARY_DIR}/resources/app/tools/tricode/"
fi

echo "Overlay source ready."

# ── Build ───────────────────────────────────────────────────────────────────

WIX_ROOT="${WIX%/}"
WIX_TOOLS="${WIX_ROOT}/bin"
if [[ ! -f "${WIX_TOOLS}/heat.exe" ]]; then
	WIX_TOOLS="${WIX_ROOT}"
fi

# Step 1: Harvest files from the overlay directory
echo "=== Harvesting bundle files ==="
"${WIX_TOOLS}/heat.exe" dir "${BINARY_DIR}" \
	-out "Files-${OUTPUT_BASE_FILENAME}.wxs" \
	-t vscodium-bundle.xsl \
	-gg -sfrag -scom -sreg -srd -ke \
	-cg "AppFiles" \
	-var var.ManufacturerName \
	-var var.AppName \
	-var var.AppCodeName \
	-var var.ProductVersion \
	-var var.BinaryDir \
	-dr APPLICATIONFOLDER \
	-platform "${PLATFORM}"

# Step 2: Compile
echo "=== Compiling bundle ==="
"${WIX_TOOLS}/candle.exe" -arch "${PLATFORM}" \
	vscodium-bundle.wxs \
	"Files-${OUTPUT_BASE_FILENAME}.wxs" \
	-ext WixUIExtension -ext WixUtilExtension \
	-dManufacturerName="TriMetaverse" \
	-dAppCodeName="${PRODUCT_CODE}" \
	-dAppName="${PRODUCT_NAME}" \
	-dProductVersion="${RELEASE_VERSION%-insider}" \
	-dProductId="${PRODUCT_ID}" \
	-dBinaryDir="${BINARY_DIR}" \
	-dCulture="${CULTURE}"

# Step 3: Link en-us MSI (single language, no transforms)
echo "=== Linking bundle ==="
"${WIX_TOOLS}/light.exe" vscodium-bundle.wixobj "Files-${OUTPUT_BASE_FILENAME}.wixobj" \
	-ext WixUIExtension -ext WixUtilExtension \
	-spdb -cc "${TEMP}\\tricade-bundle-cab-cache\\${PLATFORM}" \
	-out "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" \
	-loc "i18n-bundle\\vscodium-bundle.${CULTURE}.wxl" \
	-cultures:"${CULTURE}" \
	-sice:ICE60 -sice:ICE69

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf "${TEMP}\\tricade-bundle-cab-cache"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wxs"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wixobj"
rm -f "vscodium-bundle.wixobj"

cd "${CALLER_DIR}"

echo "=== TriCade Bundle MSI built: ${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi ==="
