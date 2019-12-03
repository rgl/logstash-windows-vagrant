param(
    [ValidateSet('oss', 'basic')]
    [string]$elasticFlavor = 'oss'
)

Import-Module Carbon
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

choco install -y adoptopenjdk8jre
Update-SessionEnvironment

$elasticsearchHome = 'C:\elasticsearch'
$elasticsearchServiceName = 'elasticsearch'
$elasticsearchServiceUsername = "NT SERVICE\$elasticsearchServiceName"
if ($elasticFlavor -eq 'oss') {
    # see https://www.elastic.co/downloads/elasticsearch-oss-no-jdk
    $archiveUrl = 'https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-oss-7.5.0-no-jdk-windows-x86_64.zip'
    $archiveHash = '86b6da0a417bf07415926f9d83fd991704bba6d8c6c63717fc3c458f9c36982673a6ceb35f29a702ac5632f0a904164f59b39d70ac02a2d8c89c9e05ce823757'
} else {
    # see https://www.elastic.co/downloads/elasticsearch-no-jdk
    $archiveUrl = 'https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.5.0-no-jdk-windows-x86_64.zip'
    $archiveHash = 'a7301fbb4f47515dad5da60eff87c60d01e9275137db8e242b49033c9623aaa5e3c25e53d2a8904c50d79d040d152b623b0337d0ad31a0bf507e5283dafad57b'
}
$archiveName = Split-Path $archiveUrl -Leaf
$archivePath = "$env:TEMP\$archiveName"

function Install-ElasticsearchPlugin($name) {
    Write-Output "Installing the $name Elasticsearch plugin..."
    cmd /C "call ""$elasticsearchHome\bin\elasticsearch-plugin.bat"" install --batch $name"
    if ($LASTEXITCODE) {
        throw "failed to install Elasticsearch plugin $name with exit code $LASTEXITCODE"
    }
}

Write-Host 'Downloading Elasticsearch...'
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA512).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}

Write-Host 'Installing Elasticsearch...'
Get-ChocolateyUnzip -FileFullPath $archivePath -Destination $elasticsearchHome
$elasticsearchArchiveTempPath = Resolve-Path $elasticsearchHome\elasticsearch-*
Move-Item $elasticsearchArchiveTempPath\* $elasticsearchHome
Remove-Item $elasticsearchArchiveTempPath
Remove-Item $archivePath

Write-Host 'Creating the Elasticsearch keystore...'
cmd.exe /c "$elasticsearchHome\bin\elasticsearch-keystore.bat" create
if ($LASTEXITCODE) {
    throw "failed to create the keystore with exit code $LASTEXITCODE"
}

# NB the service has its settings on the following registry key:
#      HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Apache Software Foundation\Procrun 2.0\elasticsearch
Write-Host "Creating the $elasticsearchServiceName service..."
$env:ES_TMPDIR = "$elasticsearchHome\tmp"
cmd.exe /c "$elasticsearchHome\bin\elasticsearch-service.bat" install $elasticsearchServiceName
if ($LASTEXITCODE) {
    throw "failed to create the $elasticsearchServiceName service with exit code $LASTEXITCODE"
}

Write-Host "Configuring the $elasticsearchServiceName service..."
$result = sc.exe sidtype $elasticsearchServiceName unrestricted
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe sidtype failed with $result"
}
$result = sc.exe config $elasticsearchServiceName obj= $elasticsearchServiceUsername
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
$result = sc.exe failure $elasticsearchServiceName reset= 0 actions= restart/1000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure failed with $result"
}
Set-Service $elasticsearchServiceName -StartupType Automatic

Write-Host 'Configuring the file system permissions...'
'logs','data','tmp' | ForEach-Object {
    mkdir -Force $elasticsearchHome\$_ | Out-Null
    Disable-AclInheritance $elasticsearchHome\$_
    Grant-Permission $elasticsearchHome\$_ Administrators FullControl
    Grant-Permission $elasticsearchHome\$_ $elasticsearchServiceUsername FullControl
}
Disable-AclInheritance $elasticsearchHome\config
Grant-Permission $elasticsearchHome\config Administrators FullControl
Grant-Permission $elasticsearchHome\config $elasticsearchServiceUsername Read
Disable-AclInheritance $elasticsearchHome\config\elasticsearch.keystore
Grant-Permission $elasticsearchHome\config\elasticsearch.keystore Administrators FullControl
Grant-Permission $elasticsearchHome\config\elasticsearch.keystore $elasticsearchServiceUsername FullControl

# install plugins.
Install-ElasticsearchPlugin 'ingest-attachment'
Install-ElasticsearchPlugin 'mapper-size'

Write-Host "Starting the $elasticsearchServiceName service..."
Start-Service $elasticsearchServiceName

# add default desktop shortcuts (called from a provision-base.ps1 generated script).
[IO.File]::WriteAllText(
    "$env:USERPROFILE\ConfigureDesktop-Elasticsearch.ps1",
@'
[IO.File]::WriteAllText(
    "$env:USERPROFILE\Desktop\Elasticsearch.url",
    @"
[InternetShortcut]
URL=http://localhost:9200
"@)
'@)
