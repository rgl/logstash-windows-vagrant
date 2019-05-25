Import-Module Carbon
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

$serviceHome = 'C:\winlogbeat'
$serviceName = 'winlogbeat'
$serviceUsername = "SYSTEM"
$archiveUrl = 'https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-oss-7.1.0-windows-x86_64.zip'
$archiveHash = '5124e90cac1f03af764b6720970ffaf9b8557646742c3b58c6916c3d3997de9c244b08023fd59a43a3030ba04cab58420e0b7007016a404a5a67ff4e2ba2aeb0'
$archiveName = Split-Path $archiveUrl -Leaf
$archivePath = "$env:TEMP\$archiveName"

Write-Host 'Downloading winlogbeat...'
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA512).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}

Write-Host 'Installing winlogbeat...'
Get-ChocolateyUnzip -FileFullPath $archivePath -Destination $serviceHome
$archiveTempPath = Resolve-Path $serviceHome\winlogbeat-*
Move-Item $archiveTempPath\* $serviceHome
Remove-Item $archiveTempPath
Remove-Item $archivePath

Write-Output "Granting write permissions to selected directories...."
@('.') | ForEach-Object {
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
@('config', 'logs', 'data') | ForEach-Object {
    mkdir -Force "$serviceHome\$_" | Out-Null
}
Remove-Item "$serviceHome\winlogbeat.yml"
Move-Item "$serviceHome\winlogbeat.reference.yml" "$serviceHome\config"
Copy-Item c:\vagrant\winlogbeat.yml "$serviceHome\config"

Write-Output "Validating the configuration..."
[string[]]$result = &"$serviceHome\winlogbeat.exe" test config -c "$serviceHome\config\winlogbeat.yml"
if ($result -ne 'Config OK') {
    throw "winlogbeat $serviceHome\config\winlogbeat.yml has errors: $result"
}

# see https://www.elastic.co/guide/en/beats/winlogbeat/current/winlogbeat-template.html#load-template-manually
Write-Output "Creating the winlogbeat Elasticsearch template..."
&"$serviceHome\winlogbeat.exe" `
    setup `
    --template `
    -c "$serviceHome\config\winlogbeat.yml" `
    -E output.logstash.enabled=false `
    -E 'output.elasticsearch.hosts=["localhost:9200"]'

Write-Output "Installing the $serviceName service..."
[string[]]$result = sc.exe `
    create `
    $serviceName `
    start= delayed-auto `
    binPath= "$serviceHome\winlogbeat.exe -c $serviceHome\config\winlogbeat.yml"
if ($result -ne '[SC] CreateService SUCCESS') {
    throw "sc.exe create failed with $result"
}
[string[]]$result = sc.exe failure $serviceName reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure failed with $result"
}

Write-Output "Starting the $serviceName service..."
Start-Service $serviceName
