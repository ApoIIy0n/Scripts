# Patch-GooglePlayGames-CustomLocation.ps1 - Patch the installer which allows custom install location
# Author: Apollyon | https://github.com/ApoIIy0n/Scripts
# Version: 1.0 (2026-09-12)

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputFile = ".\Install-GooglePlayGames.exe",

    [Parameter(Position = 1)]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This patcher is intentionally version-locked to the installer that was analysed.
# It refuses to patch anything that does not match the known SHA-256.
$KnownOriginalExeSha256 = '6AB1885D5B48921522DFBA68C9AC8234332D26C9FA5CE709C4DEF1FA6778E591'
$KnownPatchedExeSha256  = '1DE9E54B80C49E6811DF93FA1E23BFA53ED496D37C39F55001A3EB45F302DD29'

# Embedded Costura resource: costura.brandedinstallerlib.dll.compressed
$ResourceOffset = 6055812
$ResourceLength = 443614
$KnownCompressedResourceSha256 = 'E9FFB3D19F583F0E4E4FE459158C783761EAEF25FD4CD513D23AE5BF4F3ACA37'

# Uncompressed BrandedInstallerLib.dll
$KnownOriginalDllSha256 = '930C22F3F60AD3D460D67E81257F86F129EFBA479E43098198439D1A2633C6E2'
$KnownPatchedDllSha256  = 'EEE83270A8640CCBD248868856C129AA419ABDD01396074E4D8C0305CD687D58'
$KnownDllLength = 1604096

# LandingPageViewModel.get_EnforceSecureCustomInstallLocation()
# Original first three method-body bytes: 1E 02 7B
# Patched body:                       0A 17 2A
# 0A = tiny method header for 2-byte IL body
# 17 = ldc.i4.1
# 2A = ret
$DllPatchOffset = 0x4E4F
[byte[]]$ExpectedBytes = 0x1E, 0x02, 0x7B
[byte[]]$PatchedBytes  = 0x0A, 0x17, 0x2A

function Get-Sha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return ([BitConverter]::ToString($hash)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Expand-RawDeflate {
    param([Parameter(Mandatory)][byte[]]$CompressedBytes)

    $input = [System.IO.MemoryStream]::new($CompressedBytes, $false)
    $output = [System.IO.MemoryStream]::new()
    try {
        $deflate = [System.IO.Compression.DeflateStream]::new(
            $input,
            [System.IO.Compression.CompressionMode]::Decompress,
            $true
        )
        try {
            $buffer = New-Object byte[] 65536
            while (($read = $deflate.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $output.Write($buffer, 0, $read)
            }
        }
        finally {
            $deflate.Dispose()
        }

        return $output.ToArray()
    }
    finally {
        $output.Dispose()
        $input.Dispose()
    }
}

function Compress-RawDeflate {
    param([Parameter(Mandatory)][byte[]]$UncompressedBytes)

    $output = [System.IO.MemoryStream]::new()
    try {
        # Costura's resource for this installer matches DEFLATE level 6 / Optimal.
        $deflate = [System.IO.Compression.DeflateStream]::new(
            $output,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $true
        )
        try {
            $deflate.Write($UncompressedBytes, 0, $UncompressedBytes.Length)
        }
        finally {
            $deflate.Dispose()
        }

        return $output.ToArray()
    }
    finally {
        $output.Dispose()
    }
}

function Assert-Bytes {
    param(
        [Parameter(Mandatory)][byte[]]$Buffer,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][byte[]]$Expected,
        [Parameter(Mandatory)][string]$Description
    )

    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Buffer[$Offset + $i] -ne $Expected[$i]) {
            $actual = ($Buffer[$Offset..($Offset + $Expected.Length - 1)] | ForEach-Object { $_.ToString('X2') }) -join ' '
            $wanted = ($Expected | ForEach-Object { $_.ToString('X2') }) -join ' '
            throw "$Description check failed. Expected [$wanted], found [$actual]."
        }
    }
}

$InputFile = [System.IO.Path]::GetFullPath($InputFile)
if (-not [System.IO.File]::Exists($InputFile)) {
    throw "Input file not found: $InputFile"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $dir  = [System.IO.Path]::GetDirectoryName($InputFile)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $OutputFile = [System.IO.Path]::Combine($dir, "$name-custom-location-patched.exe")
}
else {
    $OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
}

if ([string]::Equals($InputFile, $OutputFile, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputFile must be different from InputFile.'
}

Write-Host "Input : $InputFile"
Write-Host "Output: $OutputFile"
Write-Host

Write-Host '[1/7] Reading and verifying installer...'
[byte[]]$exeBytes = [System.IO.File]::ReadAllBytes($InputFile)
$exeHash = Get-Sha256Hex $exeBytes
Write-Host "      SHA256: $exeHash"

if ($exeHash -eq $KnownPatchedExeSha256) {
    throw 'This installer already matches the known patched build.'
}
if ($exeHash -ne $KnownOriginalExeSha256) {
    throw @"
Unsupported installer version.

Expected:
$KnownOriginalExeSha256

Found:
$exeHash

The offsets in this patch are version-specific, so the file was NOT modified.
"@
}

if ($exeBytes.Length -lt ($ResourceOffset + $ResourceLength)) {
    throw 'Installer is unexpectedly small; embedded resource range is invalid.'
}

Write-Host '[2/7] Extracting embedded BrandedInstallerLib resource...'
[byte[]]$compressed = New-Object byte[] $ResourceLength
[Array]::Copy($exeBytes, $ResourceOffset, $compressed, 0, $ResourceLength)

$compressedHash = Get-Sha256Hex $compressed
if ($compressedHash -ne $KnownCompressedResourceSha256) {
    throw "Embedded resource hash mismatch. Found: $compressedHash"
}

Write-Host '[3/7] Decompressing embedded DLL...'
[byte[]]$dllBytes = Expand-RawDeflate $compressed
if ($dllBytes.Length -ne $KnownDllLength) {
    throw "Unexpected DLL size: $($dllBytes.Length) bytes; expected $KnownDllLength."
}

$dllHash = Get-Sha256Hex $dllBytes
if ($dllHash -ne $KnownOriginalDllSha256) {
    throw "Unexpected BrandedInstallerLib.dll SHA256: $dllHash"
}

Write-Host '[4/7] Verifying and applying feature-gate IL patch...'
Assert-Bytes -Buffer $dllBytes -Offset $DllPatchOffset -Expected $ExpectedBytes -Description 'Original IL bytes'

for ($i = 0; $i -lt $PatchedBytes.Length; $i++) {
    $dllBytes[$DllPatchOffset + $i] = $PatchedBytes[$i]
}

$patchedDllHash = Get-Sha256Hex $dllBytes
if ($patchedDllHash -ne $KnownPatchedDllSha256) {
    throw "Patched DLL verification failed. SHA256: $patchedDllHash"
}
Write-Host "      Patched DLL SHA256: $patchedDllHash"

Write-Host '[5/7] Recompressing DLL...'
[byte[]]$newCompressed = Compress-RawDeflate $dllBytes

# We patch in place. If the local .NET DEFLATE implementation produces a
# different-sized stream, do NOT shift PE resources or corrupt the executable.
if ($newCompressed.Length -ne $ResourceLength) {
    throw @"
Your PowerShell/.NET DEFLATE implementation produced $($newCompressed.Length) bytes,
but this installer requires exactly $ResourceLength bytes for an in-place patch.

Nothing was written. Try PowerShell 7 (64-bit) and run the script again.
"@
}

Write-Host '[6/7] Replacing embedded resource and writing patched EXE...'
[Array]::Copy($newCompressed, 0, $exeBytes, $ResourceOffset, $ResourceLength)

$outputDir = [System.IO.Path]::GetDirectoryName($OutputFile)
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not [System.IO.Directory]::Exists($outputDir)) {
    [System.IO.Directory]::CreateDirectory($outputDir) | Out-Null
}
[System.IO.File]::WriteAllBytes($OutputFile, $exeBytes)

Write-Host '[7/7] Verifying written file...'
[byte[]]$verifyExe = [System.IO.File]::ReadAllBytes($OutputFile)
[byte[]]$verifyCompressed = New-Object byte[] $ResourceLength
[Array]::Copy($verifyExe, $ResourceOffset, $verifyCompressed, 0, $ResourceLength)
[byte[]]$verifyDll = Expand-RawDeflate $verifyCompressed
$verifyDllHash = Get-Sha256Hex $verifyDll

if ($verifyDllHash -ne $KnownPatchedDllSha256) {
    Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue
    throw "Final verification failed; output was deleted. Embedded DLL SHA256: $verifyDllHash"
}

$outputHash = Get-Sha256Hex $verifyExe
Write-Host
Write-Host 'Patch successful.' -ForegroundColor Green
Write-Host "Output SHA256: $outputHash"

if ($outputHash -eq $KnownPatchedExeSha256) {
    Write-Host 'Output exactly matches the previously verified patched installer.' -ForegroundColor Green
}
else {
    Write-Warning 'The embedded DLL is verified, but the final EXE hash differs from the reference patched EXE. This can happen if your .NET DEFLATE implementation emits a different but same-sized valid stream.'
}

Write-Warning "The modification invalidates Google's Authenticode signature. Windows may therefore show an unsigned/untrusted publisher warning."
