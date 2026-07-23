[CmdletBinding()]
param(
    [string]$MsiPath = (Join-Path $PSScriptRoot 'releasedir\TriCade-Bundle-x64-0.2.3.msi'),
    [string]$BaseRecoveryMsiPath = (Join-Path $PSScriptRoot 'releasedir\TriCade-Bundle-x64-0.2.0.msi'),
    [string]$TargetVersion = '0.2.3'
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BundleProducts {
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    return @(Get-ItemProperty $roots -ErrorAction SilentlyContinue |
        Where-Object {
            $_.WindowsInstaller -eq 1 -and
            $_.DisplayName -like 'TriCade Bundle*' -and
            $_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$'
        })
}

function Write-RecoveryWrapper {
    param([string]$InstallLocation, [string]$BackupDirectory)

    $wrapperPath = Join-Path $InstallLocation 'resources\app\tools\trilc\trilc.cmd'
    $wrapperDirectory = Split-Path $wrapperPath -Parent
    New-Item -ItemType Directory -Path $wrapperDirectory -Force | Out-Null

    if (Test-Path $wrapperPath) {
        $backupPath = Join-Path $BackupDirectory ('trilc-before-' + [guid]::NewGuid().ToString('N') + '.cmd')
        Copy-Item $wrapperPath $backupPath -Force
    }

    $lines = @(
        '@echo off',
        'rem Recovery shim for legacy Bundle uninstall only.',
        'if /I "%~1"=="uninstall-service" exit /b 0',
        'exit /b 0'
    )
    [IO.File]::WriteAllText(
        $wrapperPath,
        (($lines -join "`r`n") + "`r`n"),
        [Text.Encoding]::ASCII
    )

    & $wrapperPath uninstall-service
    if ($LASTEXITCODE -ne 0) {
        throw "Recovery wrapper self-test failed with exit code $LASTEXITCODE"
    }
}

function Invoke-MsiExec {
    param(
        [ValidateSet('Install', 'Uninstall')]
        [string]$Operation,
        [string]$Target,
        [string]$LogPath
    )

    if ($Operation -eq 'Install') {
        $arguments = "/i `"$Target`" /qn /norestart /L*v `"$LogPath`""
    } else {
        $arguments = "/x $Target /qn /norestart /L*v `"$LogPath`""
    }

    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
        -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1605, 3010)) {
        throw "$Operation failed with Windows Installer exit code $($process.ExitCode). Log: $LogPath"
    }
}

function Expand-MsiAdministrativeImage {
    param(
        [string]$SourceMsi,
        [string]$Destination,
        [string]$LogPath
    )

    Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $arguments = "/a `"$SourceMsi`" TARGETDIR=`"$Destination`" /qn /norestart /L*v `"$LogPath`""
    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
        -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Base administrative extraction failed with exit code $($process.ExitCode). Log: $LogPath"
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated (Administrator) PowerShell window.'
}

# The caller may currently be inside Program Files\TriCade. Move the process
# working directory away before removing Bundle-owned directories.
Set-Location -LiteralPath $PSScriptRoot

$resolvedMsi = (Resolve-Path $MsiPath).Path
$resolvedBaseRecoveryMsi = (Resolve-Path $BaseRecoveryMsiPath).Path
$runningTriCade = @(Get-Process -Name 'tricade' -ErrorAction SilentlyContinue)
if ($runningTriCade.Count -gt 0) {
    throw 'Close all TriCade windows before running the repair.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDirectory = Join-Path $env:ProgramData "TriCade\InstallerRepair\$timestamp"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$service = Get-Service -Name 'TriLC' -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name 'TriLC' -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
    }
    & sc.exe delete TriLC | Out-Null
}

$installedProducts = @(Get-BundleProducts)
$installLocations = @(
    @($installedProducts | ForEach-Object { $_.InstallLocation }) +
    'C:\Program Files\TriCade'
) | Where-Object { $_ } | ForEach-Object {
    ([string]$_) -replace '[\\/]+$', ''
} | Select-Object -Unique

foreach ($product in $installedProducts) {
    $installLocation = if ($product.InstallLocation) {
        $product.InstallLocation
    } else {
        'C:\Program Files\TriCade'
    }

    Write-Host "Preparing clean uninstall for $($product.DisplayName) $($product.PSChildName)..."
    Write-RecoveryWrapper -InstallLocation $installLocation -BackupDirectory $logDirectory

    $productCodeForLog = $product.PSChildName.Trim('{}').Replace('-', '')
    $uninstallLog = Join-Path $logDirectory "uninstall-$productCodeForLog.log"
    Invoke-MsiExec -Operation Uninstall -Target $product.PSChildName -LogPath $uninstallLog
}

$remainingProducts = @(Get-BundleProducts)
if ($remainingProducts.Count -gt 0) {
    throw "Bundle registrations remain after clean uninstall: $($remainingProducts.PSChildName -join ', ')"
}

$ownedRelativePaths = @(
    'resources\app\extensions\tripilot-chat',
    'resources\app\tools\trilc',
    'resources\app\tools\tricode'
)

$allProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
foreach ($installLocation in $installLocations) {
    $installedTriLCMarker = Join-Path $installLocation 'resources\app\tools\trilc'
    foreach ($process in $allProcesses) {
        if (
            $process.ProcessId -ne $PID -and
            $process.CommandLine -and
            $process.CommandLine.IndexOf($installedTriLCMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            Write-Host "Stopping installed TriLC runtime process $($process.ProcessId)..."
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

foreach ($installLocation in $installLocations) {
    foreach ($relativePath in $ownedRelativePaths) {
        $ownedPath = Join-Path $installLocation $relativePath
        if (Test-Path $ownedPath) {
            Write-Host "Removing stale Bundle directory: $ownedPath"
            Remove-Item $ownedPath -Recurse -Force
        }
    }
}

$baseImageDirectory = Join-Path $logDirectory 'base-image'
$baseExtractLog = Join-Path $logDirectory 'base-extract.log'
Write-Host "Extracting TriCade Base recovery image..."
Expand-MsiAdministrativeImage `
    -SourceMsi $resolvedBaseRecoveryMsi `
    -Destination $baseImageDirectory `
    -LogPath $baseExtractLog

$baseExecutable = Get-ChildItem $baseImageDirectory -Recurse -Filter 'tricade.exe' -File |
    Select-Object -First 1
if (-not $baseExecutable) {
    throw "TriCade Base executable was not found in the administrative image: $baseImageDirectory"
}

$baseSourceRoot = $baseExecutable.DirectoryName
$baseInstallLocation = $installLocations | Select-Object -First 1
$excludedBaseDirectories = @(
    (Join-Path $baseSourceRoot 'resources\app\extensions\tripilot-chat'),
    (Join-Path $baseSourceRoot 'resources\app\tools\trilc'),
    (Join-Path $baseSourceRoot 'resources\app\tools\tricode')
)
$robocopyArguments = @(
    $baseSourceRoot,
    $baseInstallLocation,
    '/E',
    '/COPY:DAT',
    '/DCOPY:DAT',
    '/R:2',
    '/W:1',
    '/NFL',
    '/NDL',
    '/NJH',
    '/NJS',
    '/NP',
    '/XD'
) + $excludedBaseDirectories

Write-Host "Restoring TriCade Base files to $baseInstallLocation..."
& robocopy.exe @robocopyArguments
$robocopyExitCode = $LASTEXITCODE
if ($robocopyExitCode -ge 8) {
    throw "TriCade Base restore failed with robocopy exit code $robocopyExitCode"
}

$baseRegistryKey = 'HKLM:\SOFTWARE\TriMetaverse\TriCade'
New-Item -Path $baseRegistryKey -Force | Out-Null
Set-ItemProperty -Path $baseRegistryKey -Name 'Path' -Value $baseInstallLocation

$installLog = Join-Path $logDirectory "install-$TargetVersion.log"
Invoke-MsiExec -Operation Install -Target $resolvedMsi -LogPath $installLog

$installedTarget = @(Get-BundleProducts | Where-Object { $_.DisplayVersion -eq $TargetVersion })
if ($installedTarget.Count -ne 1) {
    throw "Expected exactly one TriCade Bundle $TargetVersion registration; found $($installedTarget.Count)."
}

$installedRoot = $installedTarget[0].InstallLocation
if (-not $installedRoot) {
    $installedRoot = 'C:\Program Files\TriCade'
}
$installedTripilot = Join-Path $installedRoot 'resources\app\extensions\tripilot-chat\out\extension.js'
$installedTriLC = Join-Path $installedRoot 'resources\app\tools\trilc\dist\server\app.js'
$installedWrapper = Join-Path $installedRoot 'resources\app\tools\trilc\trilc.cmd'
$installedCodiconCss = Join-Path $installedRoot 'resources\app\extensions\tripilot-chat\node_modules\@vscode\codicons\dist\codicon.css'
$installedCodiconFont = Join-Path $installedRoot 'resources\app\extensions\tripilot-chat\node_modules\@vscode\codicons\dist\codicon.ttf'
$installedBaseExecutable = Join-Path $installedRoot 'tricade.exe'
$installedProductJson = Join-Path $installedRoot 'resources\app\product.json'
$installedWorkbench = Join-Path $installedRoot 'resources\app\out\vs\workbench\workbench.desktop.main.js'

if (-not (Test-Path $installedBaseExecutable)) {
    throw "TriCade Base executable is missing after recovery: $installedBaseExecutable"
}
if (-not (Test-Path $installedProductJson)) {
    throw "TriCade Base product metadata is missing after recovery: $installedProductJson"
}
if (-not (Test-Path $installedWorkbench)) {
    throw "TriCade Base workbench is missing after recovery: $installedWorkbench"
}
if (-not (Select-String -Path $installedTripilot -Pattern 'taskError' -Quiet)) {
    throw "Installed Tripilot does not contain the task_error propagation fix: $installedTripilot"
}
if (Select-String -Path $installedTripilot -Pattern 'Always refer to yourself as 小T|You are Tripilot \(小T\)' -Quiet) {
    throw "Installed Tripilot still contains the retired 小T persona."
}
if (-not (Select-String -Path $installedTripilot -Pattern 'trilcSystemInstruction = instruction' -Quiet)) {
    throw "Installed Tripilot does not submit the selected Contract system prompt."
}
if (-not (Select-String -Path $installedTriLC -Pattern 'model: entry.model' -Quiet)) {
    throw "Installed TriLC does not contain the cached-model routing fix: $installedTriLC"
}
if (-not (Test-Path $installedCodiconCss) -or -not (Test-Path $installedCodiconFont)) {
    throw "Installed Tripilot is missing codicon CSS or font assets."
}

$wrapperBytes = [IO.File]::ReadAllBytes($installedWrapper)
for ($index = 0; $index -lt $wrapperBytes.Length; $index++) {
    if ($wrapperBytes[$index] -eq 10 -and ($index -eq 0 -or $wrapperBytes[$index - 1] -ne 13)) {
        throw "Installed trilc.cmd contains a non-CRLF line ending: $installedWrapper"
    }
}

Write-Host "TriCade Bundle repair completed. Installed version: $TargetVersion"
Write-Host "Logs: $logDirectory"