param(
    [ValidateSet('oss', 'basic')]
    [string]$elasticFlavor = 'oss'
)

Import-Module Carbon
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

$serviceHome = 'C:\winlogbeat'
$serviceName = 'winlogbeat'
$serviceUsername = "SYSTEM"
if ($elasticFlavor -eq 'oss') {
    # see https://www.elastic.co/downloads/beats/winlogbeat-oss
    $archiveUrl = 'https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-oss-7.6.1-windows-x86_64.zip'
    $archiveHash = '9d1c760b20c2c0b16b608e80084bf3d4dab0738e23d721276863c680c4cf1aa047494eaeb3f601b7424431d5e19848180c420f63255b6f20fbc2656ba451fdbc'
} else {
    # see https://www.elastic.co/downloads/beats/winlogbeat
    $archiveUrl = 'https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-7.6.1-windows-x86_64.zip'
    $archiveHash = 'c49ba02bd56994f608a09ed37237289eef9e2f251d59d1d5d25e2cb327acec2c1a6c14191228109fefe0b8057be81766892080004400b7585e5b13673665edb9'
}
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
    --index-management `
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
$templateName = "winlogbeat-$($archiveName -replace '.+-(\d+(\.\d+)+).+','$1')"
Write-Output "Enabling the _size field in the $templateName template..."
Enable-ElasticsearchTemplateSizeMapping $templateName
