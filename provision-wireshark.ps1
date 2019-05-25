choco install -y wireshark

# leave npcap on the desktop for the user to install manually.
# (it does not have a silent installer).
$url = 'https://nmap.org/npcap/dist/npcap-0.995.exe'
$expectedHash = 'e0274413bf2178c66680a4ee69c4fa871bf7296ea1d9d9a6d19af32a3878c205'
$localPath = "$env:USERPROFILE\Desktop\$(Split-Path -Leaf $url)"
(New-Object Net.WebClient).DownloadFile($url, $localPath)
$actualHash = (Get-FileHash $localPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "downloaded file from $url to $localPath has $actualHash hash that does not match the expected $expectedHash"
}

# add default desktop shortcuts (called from a provision-base.ps1 generated script).
[IO.File]::WriteAllText(
    "$env:USERPROFILE\ConfigureDesktop-Wireshark.ps1",
@'
Install-ChocolateyShortcut `
    -ShortcutFilePath "$env:USERPROFILE\Desktop\Wireshark.lnk" `
    -TargetPath 'C:\Program Files\Wireshark\Wireshark.exe'
'@)
