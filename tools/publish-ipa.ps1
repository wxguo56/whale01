<#
Publishes the newest successfully built sideload IPA to the fixed drop folder.

Usage:
    pwsh tools/publish-ipa.ps1                 # latest successful "iOS Sideload IPA" run
    pwsh tools/publish-ipa.ps1 -RunId 123456   # publish a specific run

Always overwrites C:\Users\<user>\WhaleAgent-Sideload.ipa and its .sha256 sidecar.
#>
[CmdletBinding()]
param(
    [long]$RunId = 0,
    [string]$Repo = "wxguo56/whale01",
    [string]$Destination = (Join-Path $env:USERPROFILE "WhaleAgent-Sideload.ipa"),
    [string]$IpaPass = $env:IPA_PASS,
    [string]$PrivateKeyPath = (Join-Path $env:USERPROFILE ".whale\ipa-private.pem")
)

$ErrorActionPreference = "Stop"

function Get-GitHubToken {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    $cred = @("protocol=https", "host=github.com", "") | git credential fill 2>$null
    $match = $cred | Select-String -Pattern '^password=(.+)$'
    if (-not $match) { throw "No GitHub token found in GITHUB_TOKEN or the git credential manager." }
    return $match.Matches[0].Groups[1].Value
}

$token = Get-GitHubToken
$headers = @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "User-Agent" = "whale-publish-ipa"
}

if ($RunId -eq 0) {
    $runs = (Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs?per_page=20" -Headers $headers).workflow_runs
    $run = $runs | Where-Object { $_.name -eq "iOS Sideload IPA" -and $_.status -eq "completed" -and $_.conclusion -eq "success" } | Select-Object -First 1
    if (-not $run) { throw "No successful iOS Sideload IPA run found." }
    $RunId = $run.id
}

$artifacts = (Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs/$RunId/artifacts" -Headers $headers).artifacts
$artifact = $artifacts | Where-Object { $_.name -eq "WhaleAgent-Sideload-ipa-enc" } | Select-Object -First 1
$encrypted = $true
if (-not $artifact) {
    $artifact = $artifacts | Where-Object { $_.name -eq "WhaleAgent-Sideload-ipa" } | Select-Object -First 1
    $encrypted = $false
}
if (-not $artifact) { throw "Run $RunId has no WhaleAgent-Sideload IPA artifact." }

$work = Join-Path $env:TEMP ("whale-publish-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$zip = Join-Path $work "ipa.zip"

Invoke-WebRequest -Uri "https://api.github.com/repos/$Repo/actions/artifacts/$($artifact.id)/zip" -Headers $headers -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $work -Force
$ipa = Get-ChildItem -Path $work -Recurse -Filter "WhaleAgent-Sideload.ipa" | Select-Object -First 1
if (-not $ipa) {
    $enc = Get-ChildItem -Path $work -Recurse -Filter "WhaleAgent-Sideload.ipa.enc" | Select-Object -First 1
    if (-not $enc) { throw "Artifact did not contain a usable IPA or encrypted IPA." }
    if (-not $encrypted) { throw "Found an encrypted IPA in an unexpected artifact." }
    if (-not $IpaPass) {
        $wrapped = Get-ChildItem -Path $work -Recurse -Filter "WhaleAgent-pass.enc" | Select-Object -First 1
        if ($wrapped -and (Test-Path -LiteralPath $PrivateKeyPath)) {
            $rsa = [System.Security.Cryptography.RSA]::Create()
            $rsa.ImportFromPem((Get-Content -LiteralPath $PrivateKeyPath -Raw))
            $passBytes = $rsa.Decrypt(
                [System.IO.File]::ReadAllBytes($wrapped.FullName),
                [System.Security.Cryptography.RSAEncryptionPadding]::Pkcs1
            )
            $rsa.Dispose()
            $IpaPass = [System.Text.Encoding]::UTF8.GetString($passBytes).Trim()
        }
    }
    if (-not $IpaPass) { throw "Artifact is encrypted. Provide -IpaPass, set IPA_PASS, or place the RSA private key at $PrivateKeyPath." }

    # OpenSSL-compatible: "Salted__" + 8-byte salt, AES-256-CBC, PBKDF2-HMAC-SHA256, 10000 rounds.
    $raw = [System.IO.File]::ReadAllBytes($enc.FullName)
    $magic = [System.Text.Encoding]::ASCII.GetString($raw, 0, 8)
    if ($magic -ne "Salted__") { throw "Encrypted IPA is not in OpenSSL salted format." }
    $salt = $raw[8..15]
    $cipherLength = $raw.Length - 16
    $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $IpaPass,
        $salt,
        10000,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $key = $kdf.GetBytes(32)
    $iv = $kdf.GetBytes(16)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $key
    $aes.IV = $iv
    $decryptor = $aes.CreateDecryptor()
    $plain = $decryptor.TransformFinalBlock($raw, 16, $cipherLength)
    $ipaPath = Join-Path $work "WhaleAgent-Sideload.ipa"
    [System.IO.File]::WriteAllBytes($ipaPath, $plain)
    $aes.Dispose()
    $kdf.Dispose()
    $ipa = Get-Item -LiteralPath $ipaPath
    Write-Host "decrypted IPA_PASS artifact"
}

$destinationDir = Split-Path -Parent $Destination
New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
Copy-Item -LiteralPath $ipa.FullName -Destination $Destination -Force

$hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLower()
$sidecar = "$Destination.sha256"
"$hash  WhaleAgent-Sideload.ipa" | Set-Content -Path $sidecar -Encoding ascii
$size = (Get-Item -LiteralPath $Destination).Length

$identity = "unknown"
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $probe = Join-Path $work "probe.py"
    @"
import plistlib, zipfile
with zipfile.ZipFile(r'$Destination') as z:
    with z.open('Payload/WhaleAgent.app/Info.plist') as f:
        info = plistlib.load(f)
print(info.get('CFBundleShortVersionString', '?'), info.get('CFBundleVersion', '?'))
"@ | Set-Content -Path $probe -Encoding utf8
    $identity = (& $python.Source $probe).Trim()
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "published run $RunId -> $Destination"
Write-Host "version/build: $identity"
Write-Host "size: $size bytes"
Write-Host "sha256: $hash"
