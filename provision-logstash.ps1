param(
    [ValidateSet('oss', 'basic')]
    [string]$elasticFlavor = 'oss'
)

Import-Module Carbon
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

$serviceHome = 'C:\logstash'
$serviceName = 'logstash'
$serviceUsername = "NT SERVICE\$serviceName"
if ($elasticFlavor -eq 'oss') {
    # see https://www.elastic.co/downloads/logstash-oss
    $archiveUrl = 'https://artifacts.elastic.co/downloads/logstash/logstash-oss-7.6.1.zip'
    $archiveHash = '79468eeeb3b1b42f43475745a91db603442181461dc402f5c13914eff3ceae33bbb811bbf7a0114ed6a06252414eee05a9311bd1c8766dec649e642e1e324aef'
} else {
    # see https://www.elastic.co/downloads/logstash
    $archiveUrl = 'https://artifacts.elastic.co/downloads/logstash/logstash-7.6.1.zip'
    $archiveHash = '8dcd6aa5a8049e43f155bc113dd95bd6fbcbf6184a5fa2de0540df96e6385b69791de5ca36b62a57126b925afbe7de2f86cbd6d7a8f0130c6aa8b38859b08447'
}
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

# enable the _size property to account the size of each document _source property length.
# see https://www.elastic.co/guide/en/elasticsearch/plugins/current/mapper-size.html
function Enable-ElasticsearchTemplateSizeMapping($templateName) {
    $templateUrl = "http://localhost:9200/_template/$templateName"
    # wait for the template to appear (the application might still be creating it in the background).
    while ($true) {
        try {
            $template = (Invoke-RestMethod -Uri $templateUrl).$templateName
            break
        }
        catch {
            Start-Sleep -Seconds 3
        }
    }
    $template.mappings | Add-Member -NotePropertyName _size -NotePropertyValue @{enabled=$true}
    $templateJson = $template | ConvertTo-Json -Depth 100
    $result = Invoke-RestMethod `
        -Method Put `
        -Uri $templateUrl `
        -ContentType 'application/json' `
        -Body $templateJson
    if (!$result.acknowledged) {
        throw "failed to set the elasticsearch template size mapping: $($result | ConvertTo-Json -Compress)"
    }
}
$templateName = 'logstash'
Write-Output "Enabling the _size field in the $templateName template..."
Enable-ElasticsearchTemplateSizeMapping $templateName
