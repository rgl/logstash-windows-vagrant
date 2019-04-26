choco install -y wireshark

# leave npcap on the desktop for the user to install manually.
# (it does not have a silent installer).
$url = 'https://nmap.org/npcap/dist/npcap-0.992.exe'
$expectedHash = 'a41d6e8296ef55c71fc04c5775e5d0e5d04689fc2aaf7f6f908664db9670a1f9'
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
