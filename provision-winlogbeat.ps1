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
    $archiveUrl = 'https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-oss-7.4.2-windows-x86_64.zip'
    $archiveHash = '4e10fa1dc572df0070dfb9dfcc955248fb55ae111043f204f65c9891ac9a2f54aed05757b46a1b3e4bc7263172afa0c7a85cd54a74bfc7b7e5febea8c1df938a'
} else {
    # see https://www.elastic.co/downloads/beats/winlogbeat
    $archiveUrl = 'https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-7.4.2-windows-x86_64.zip'
    $archiveHash = '74ed363308589b5393b185d1684c5ea340dd975bb6886db72250f16cfd5347d52221f5b73865cdf076a64b008b76e4a613407f89f01e826e1e7c75717b7ce892'
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
