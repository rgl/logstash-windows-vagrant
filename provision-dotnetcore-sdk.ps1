# see https://dotnet.microsoft.com/download/dotnet-core/2.1
# see https://github.com/dotnet/core/blob/master/release-notes/2.1/2.1.16/2.1.804-download.md

# opt-out from dotnet telemetry.
[Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'Machine')
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'

# install the dotnet sdk.
$archiveUrl = 'https://download.visualstudio.microsoft.com/download/pr/0ec90d98-54fd-4bfc-9f36-c946abf15d9e/852c978e4377c898f5ccd36b1663cd55/dotnet-sdk-2.1.804-win-x64.exe'
$archiveHash = '411b2e9afbbb44ef7239ee9e83dc1db61049473b36edea09e184f98a2cf9f10499dbc8d043df069af86625392154a09d26843edeaadffa0113edd7380d32161f'
$archiveName = Split-Path -Leaf $archiveUrl
$archivePath = "$env:TEMP\$archiveName"
Write-Host "Downloading $archiveName..."
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA512).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}
Write-Host "Installing $archiveName..."
&$archivePath /install /quiet /norestart | Out-String -Stream
if ($LASTEXITCODE) {
    throw "Failed to install dotnetcore-sdk with Exit Code $LASTEXITCODE"
}
Remove-Item $archivePath

# reload PATH.
$env:PATH = "$([Environment]::GetEnvironmentVariable('PATH', 'Machine'));$([Environment]::GetEnvironmentVariable('PATH', 'User'))"

# show information about dotnet.
dotnet --info

# install the sourcelink dotnet global tool.
dotnet tool install --global sourcelink

# make sure the SYSTEM account PATH environment variable is empty because,
# for some reason, the sdk setup changes it to include private directories
# which cannot be accessed by anyone but the user that installed the sdk.
# see https://github.com/dotnet/core/issues/1942.
# NB the .DEFAULT key is for the local SYSTEM account (S-1-5-18).
New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
New-ItemProperty `
    -Path HKU:\.DEFAULT\Environment `
    -Name Path `
    -Value '' `
    -PropertyType ExpandString `
    -Force `
    | Out-Null
Remove-PSDrive HKU
