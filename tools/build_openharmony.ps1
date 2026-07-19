# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

param(
    [Parameter(Mandatory = $true)]
    [string]$OpenHarmonySdkHome,
    [string]$DevEcoHome = 'D:\Program Files\Huawei\DevEco Studio',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sdk = (Resolve-Path -LiteralPath $OpenHarmonySdkHome).Path
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path -LiteralPath $hvigor -PathType Leaf)) {
    throw "hvigorw.bat not found: $hvigor"
}
$nodeHome = Join-Path $DevEcoHome 'tools\node'
if (-not (Test-Path -LiteralPath (Join-Path $nodeHome 'node.exe') -PathType Leaf)) {
    throw "DevEco bundled node.exe not found: $nodeHome"
}
if ($OutputRoot.Length -eq 0) {
    $OutputRoot = Join-Path $repo 'dist\openharmony-build'
}
$target = [System.IO.Path]::GetFullPath($OutputRoot)
$distRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'dist'))
$distPrefix = $distRoot.TrimEnd('\') + '\'
if (-not $target.StartsWith($distPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must stay under the repository dist directory.'
}
if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Path $target | Out-Null

$skip = '^(\.git|\.agents|\.hvigor|\.idea|\.preview|dist|signing|oh_modules|node_modules|entry[\\/]build|entry[\\/]\.preview|gateway[\\/]esp32s3m[\\/]build|gateway[\\/]esp32s3m[\\/]managed_components|tmp_pdf_extract)([\\/]|$)|(^|[\\/])sdkconfig(\.old)?$|\.(p12|pem|p7b|cer|hap|key|log|pyc|msgpack)$|__pycache__'
Get-ChildItem -LiteralPath $repo -Recurse -File | ForEach-Object {
    # Windows PowerShell 5.1 runs on .NET Framework, which does not expose
    # System.IO.Path.GetRelativePath. Every enumerated file is below $repo, so
    # deriving the relative path by removing the verified repository prefix is
    # both compatible and unambiguous here.
    if (-not $_.FullName.StartsWith($repo + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "File escaped repository root: $($_.FullName)"
    }
    $relative = $_.FullName.Substring($repo.Length).TrimStart([char[]]'\/')
    if ($relative -notmatch $skip -and $relative -ne 'build-profile.json5' -and $relative -ne 'entry\src\main\module.json5') {
        $destination = Join-Path $target $relative
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination
    }
}
Copy-Item -LiteralPath (Join-Path $repo 'config\build-profile.openharmony.template.json5') -Destination (Join-Path $target 'build-profile.json5')
Copy-Item -LiteralPath (Join-Path $repo 'config\module.openharmony.template.json5') -Destination (Join-Path $target 'entry\src\main\module.json5')

$env:DEVECO_SDK_HOME = $sdk
$env:OHOS_BASE_SDK_HOME = $sdk
$env:NODE_HOME = $nodeHome
$env:PATH = "$nodeHome;$env:PATH"
Push-Location $target
try {
    & $hvigor --no-daemon --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap
    if ($LASTEXITCODE -ne 0) {
        throw "OpenHarmony HAP build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
Write-Host "OpenHarmony build workspace: $target"
