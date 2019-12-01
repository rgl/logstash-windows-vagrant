Import-Module Carbon
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

$serviceHome = 'C:\logstash'
$serviceName = 'logstash'
$serviceUsername = "NT SERVICE\$serviceName"
# see https://www.elastic.co/downloads/logstash-oss
$archiveUrl = 'https://artifacts.elastic.co/downloads/logstash/logstash-oss-7.4.2.zip'
$archiveHash = '71abe986dd88846aa715a8c0bcd1729f6cab8fbcdd5b43dab762a334b2ec6c11049131a7a96e571d3be88ef1aa3586874386d0d8319496ba5354b425ac96c415'
$archiveName = Split-Path $archiveUrl -Leaf
$archivePath = "$env:TEMP\$archiveName"

Write-Host 'Downloading logstash...'
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA512).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}

Write-Host 'Installing logstash...'
Get-ChocolateyUnzip -FileFullPath $archivePath -Destination $serviceHome
$archiveTempPath = Resolve-Path $serviceHome\logstash-*
Move-Item $archiveTempPath\* $serviceHome
Remove-Item $archiveTempPath
Remove-Item $archivePath

Write-Output "Installing the $serviceName service..."
nssm install $serviceName $serviceHome\bin\logstash.bat
nssm set $serviceName Start SERVICE_AUTO_START
nssm set $serviceName AppDirectory $serviceHome
nssm set $servicename AppParameters -f config/logstash.conf
nssm set $serviceName AppRotateFiles 1
nssm set $serviceName AppRotateOnline 1
nssm set $serviceName AppRotateSeconds 86400
nssm set $serviceName AppRotateBytes (10*1024*1024) # 10MB
nssm set $serviceName AppStdout $serviceHome\logs\$serviceName-stdout.log
nssm set $serviceName AppStderr $serviceHome\logs\$serviceName-stderr.log
[string[]]$result = sc.exe sidtype $serviceName unrestricted
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe sidtype failed with $result"
}
[string[]]$result = sc.exe config $serviceName obj= $serviceUsername
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
[string[]]$result = sc.exe failure $serviceName reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure failed with $result"
}

Write-Output "Granting write permissions to selected directories...."
@('data', 'logs') | ForEach-Object {
    $path = "$serviceHome\$_"
    mkdir -Force $path | Out-Null
    Disable-AclInheritance $path
    'Administrators',$serviceUsername | ForEach-Object {
        Write-Host "Granting $_ FullControl to $path..."
        Grant-Permission `
            -Identity $_ `
            -Permission FullControl `
            -Path $path
    }
}
Copy-Item c:\vagrant\logstash.conf $serviceHome\config

Write-Output "Starting the $serviceName service..."
Start-Service $serviceName
