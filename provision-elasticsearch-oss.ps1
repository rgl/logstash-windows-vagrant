Import-Module Carbon

choco install -y adoptopenjdk8jre
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"
Update-SessionEnvironment

$elasticsearchHome = 'C:\elasticsearch'
$elasticsearchServiceName = 'elasticsearch'
$elasticsearchServiceUsername = "NT SERVICE\$elasticsearchServiceName"
$archiveUrl = 'https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-oss-6.7.0.zip'
$archiveHash = '1e86793b2ce8ce049e2c600d20986bf5b294ab29f402de180c7efa57a1d945162d6bf1ddcb221d6c7aca9553bcb46ed150c8df7dfa14254b0727dc98cf0f5ffb'
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
mkdir $elasticsearchHome | Out-Null
Expand-Archive $archivePath -DestinationPath $elasticsearchHome
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
