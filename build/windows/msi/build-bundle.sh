#!/usr/bin/env bash
#
# build-bundle.sh �?TriCade Bundle MSI (TriMetaverse components only).
#
# Usage:  VSCODE_ARCH=x64 RELEASE_VERSION=0.2.3 WIX=/path/to/wix/ ./build-bundle.sh
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

# Default to independent TriCade version (decoupled from VSCodium)
RELEASE_VERSION="${RELEASE_VERSION:-0.2.6}"

CALLER_DIR=$( pwd )

cd "$( dirname "${BASH_SOURCE[0]}" )"

WIN_SDK_MAJOR_VERSION="10"
WIN_SDK_FULL_VERSION="10.0.22621.0"

# ── Bundle product identity ─────────────────────────────────────────────────
PRODUCT_NAME="TriCade Bundle"
PRODUCT_CODE="TriCadeBundle"
# Independent UpgradeCode �?Bundle is a separate MSI product from Base
PRODUCT_UPGRADE_CODE="{8F7A2B1C-D3E4-5678-9ABC-DEF012345678}"

PRODUCT_ID=$( powershell.exe -command "[guid]::NewGuid().ToString().ToUpper()" )
PRODUCT_ID="${PRODUCT_ID%%[[:cntrl:]]}"

CULTURE="en-us"

SETUP_RELEASE_DIR=".\\releasedir"

# ── Source repositories (absolute paths) ────────────────────────────────────
TRIPILOT_DIR="D:\\OneDrive\\Code\\ai\\TriPilot"
TRILC_DIR="D:\\OneDrive\\Code\\ai\\TriLC"
TRICODE_DIR="D:\\OneDrive\\Code\\ai\\TriCode"
TRICOMPANY_SOURCE_DIR="D:\\OneDrive\\Code\\ai\\TriCompany\\source-agents"
TRIMC_AGENT_CORE_DIR="D:\\OneDrive\\Code\\ai\\TriMC\\packages\\agent-core"
TRIMODEL_DIR="D:\\OneDrive\\Code\\ai\\TriModel"

# ── BINARY_DIR: overlay structure mimicking the TriCade install tree ────────
# heat.exe crawls this and maps it under APPLICATIONFOLDER (i.e. %ProgramFiles%\TriCade\).
# Structure:
#   resources/
#     app/
#       extensions/
#         tripilot-chat/    �?TriPilot out/ + package.json
#       tools/
#         trilc/             �?TriLC dist/ + node_modules + runtime contracts
#         tricode/           �?TriCode dist/ + package.json
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

# Start from a deterministic staging tree. A full Base is copied later only
# when VSCODE_BASE_DIR is explicitly provided.
rm -rf "${BINARY_DIR}"
mkdir -p "${BINARY_DIR}"
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
TRIPILOT_STAGE="${BINARY_DIR}/resources/app/extensions/tripilot-chat"
CODICONS_SOURCE="${TRIPILOT_DIR}/node_modules/@vscode/codicons"
if [[ ! -f "${CODICONS_SOURCE}/dist/codicon.css" || ! -f "${CODICONS_SOURCE}/dist/codicon.ttf" ]]; then
	echo "Missing Tripilot codicon assets under ${CODICONS_SOURCE}/dist" >&2
	exit 1
fi
mkdir -p "${TRIPILOT_STAGE}/node_modules/@vscode"
cp -r "${CODICONS_SOURCE}" "${TRIPILOT_STAGE}/node_modules/@vscode/"
if [[ ! -f "${TRIPILOT_STAGE}/node_modules/@vscode/codicons/dist/codicon.css" || ! -f "${TRIPILOT_STAGE}/node_modules/@vscode/codicons/dist/codicon.ttf" ]]; then
	echo "Tripilot codicon assets were not staged correctly" >&2
	exit 1
fi
echo "  ✓ Tripilot codicon CSS and font collected"

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
	"yaml@^2.9.0" \
	"marked@^12.0.2" \
	"ink@^5.2.0"
if [[ -f "${TRILC_DIR}/package.json" ]]; then
	cp "${TRILC_DIR}/package.json" "${TRILC_STAGE}/"
fi
(
	cd "${TRILC_STAGE}"
	node --input-type=module -e "await import('@trimetaverse/agent-core'); await import('trimodel'); await import('yaml');"
	echo "  ✓ TriLC production imports verified (agent-core + trimodel + yaml)"
)

# --- TriLC default .env (key-cache bootstrap token) ---
# dotenv (via trimodel) loads this at daemon startup so key-cache can
# authenticate to the TriModel config-plane API on port 3333.
echo "Generating trilc .env (default API token)..."
cat > "${TRILC_STAGE}/.env" << 'TRILCENVEOF'
TRIMODEL_API_TOKEN=tmv-sk-dev-local
TRILCENVEOF
echo "  ✓ trilc .env written with TRIMODEL_API_TOKEN"

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

# --- TriLC Tray (conditional: arch-trilc-tray output) ---
echo "Collecting TriLC Tray..."
TRILC_TRAY_EXE="${TRILC_DIR}/src/tray/bin/Release/net8.0-windows/win-x64/publish/TriLC.Tray.exe"
if [[ -f "${TRILC_TRAY_EXE}" ]]; then
	mkdir -p "${BINARY_DIR}/resources/app/tools/trilc/tray"
	cp "${TRILC_TRAY_EXE}" "${BINARY_DIR}/resources/app/tools/trilc/tray/"
	# Copy tray dependencies if publish directory exists
	if [[ -d "$(dirname "${TRILC_TRAY_EXE}")" ]]; then
		cp -r "$(dirname "${TRILC_TRAY_EXE}")"/* "${BINARY_DIR}/resources/app/tools/trilc/tray/" 2>/dev/null || true
	fi
	echo "  ✓ TriLC.Tray.exe collected"
else
	echo "  ⚠ TriLC.Tray.exe not found at ${TRILC_TRAY_EXE} — skipping (Tray not yet built)"
fi

# --- Generate trilc.cmd wrapper for MSI CustomAction ---
echo "Generating trilc.cmd wrapper..."
TRILC_CMD_PATH="${BINARY_DIR}/resources/app/tools/trilc/trilc.cmd"
cat > "${TRILC_CMD_PATH}" << 'CMDEOF'
@echo off
setlocal enabledelayedexpansion
set TRILC_DIR=%~dp0
set TRILC_CLI=%TRILC_DIR%dist\cli.js

REM Strategy: probe VSCodium Base bundled Node.js first,
REM fall back to system PATH node.
REM VSCodium ships node.exe in bin\ or directly in install root.
set NODE_EXE=

REM Probe 1: ..\..\..\..\bin\node.exe → TriCade\bin\node.exe
if exist "%TRILC_DIR%..\..\..\..\bin\node.exe" (
    set NODE_EXE=%TRILC_DIR%..\..\..\..\bin\node.exe
    goto :run
)

REM Probe 2: system PATH
where node >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set NODE_EXE=node
    goto :run
)

echo [trilc] ERROR: Node.js not found. Cannot run TriLC CLI.
echo [trilc] Please install Node.js >=20 or ensure TriCade Base is installed.
exit /b 1

:run
"!NODE_EXE!" "%TRILC_CLI%" %*
exit /b %ERRORLEVEL%
CMDEOF
node -e "const fs=require('node:fs');const p=process.argv[1];const text=fs.readFileSync(p,'utf8').replace(/\r?\n/g,'\r\n');fs.writeFileSync(p,text,'ascii');const bytes=fs.readFileSync(p);for(let i=0;i<bytes.length;i++){if(bytes[i]===10&&bytes[i-1]!==13)throw new Error('trilc.cmd contains a non-CRLF line ending')}" "${TRILC_CMD_PATH}"
echo "  ✓ trilc.cmd generated with CRLF line endings"

echo "Overlay source ready."

# Copy VSCodium base (tricade.exe, bin/, etc.) — exclude resources/ to avoid overlay collision
echo "Copying VSCodium base into bundle..."
if [[ -d "${VSCODE_BASE_DIR}" ]]; then
	# Copy root-level files and non-resources directories only
	for item in "${VSCODE_BASE_DIR}/"*; do
		base=$(basename "$item")
		if [[ "$base" != "resources" ]]; then
			if [[ -d "$item" ]]; then
				cp -r "$item" "${BINARY_DIR}/" 2>/dev/null || true
			else
				cp "$item" "${BINARY_DIR}/" 2>/dev/null || true
			fi
		fi
	done
	echo "  ✓ Base copied from ${VSCODE_BASE_DIR}"
else
	echo "  ⚠ VSCODE_BASE_DIR not set or not found — skipping base"
fi

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

# ── Artifact Verification ──
echo ""
echo "=== Verifying MSI artifact ==="
MSI_PATH="${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi"

# 1. File existence + size sanity
if [[ ! -f "${MSI_PATH}" ]]; then
	echo "ERROR: MSI not found at ${MSI_PATH}"
	exit 1
fi
MSI_SIZE=$( stat -c%s "${MSI_PATH}" 2>/dev/null || wc -c < "${MSI_PATH}" )
echo "  MSI size: ${MSI_SIZE} bytes"

# Expected range: 2-20 MB
if [[ ${MSI_SIZE} -lt 2000000 ]] || [[ ${MSI_SIZE} -gt 20000000 ]]; then
	echo "  ⚠ WARNING: MSI size outside expected 2-20 MB range"
fi

# 2. SHA-256 hash
if command -v sha256sum &>/dev/null; then
	sha256sum "${MSI_PATH}" | tee "${MSI_PATH}.sha256"
elif command -v certutil &>/dev/null; then
	certutil -hashfile "${MSI_PATH}" SHA256 | findstr /V "hash" > "${MSI_PATH}.sha256"
	cat "${MSI_PATH}.sha256"
fi
echo "  SHA-256 → ${MSI_PATH}.sha256"

# 3. Version verification
echo "  MSI version: ${RELEASE_VERSION}"
echo "  ProductCode: ${PRODUCT_ID}"

echo "=== Verification complete ==="
