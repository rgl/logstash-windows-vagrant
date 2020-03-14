param(
    [ValidateSet('oss', 'basic')]
    [string]$elasticFlavor = 'oss'
)

Import-Module Carbon
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

$serviceHome = 'C:\kibana'
$serviceName = 'kibana'
$serviceUsername = "NT SERVICE\$serviceName"
if ($elasticFlavor -eq 'oss') {
    # see https://www.elastic.co/downloads/kibana-oss
    $archiveUrl = 'https://artifacts.elastic.co/downloads/kibana/kibana-oss-7.6.1-windows-x86_64.zip'
    $archiveHash = 'da1f4513aee732d8ada14b6e5dbfa28fd9afbddf6ab55725dee28fa80d08e22387044a5aed2c23a028ee72d8a32e2c97493f78595bbd7fa4f3f7ef10c5cbd4d4'
} else {
    # see https://www.elastic.co/downloads/kibana
    $archiveUrl = 'https://artifacts.elastic.co/downloads/kibana/kibana-7.6.1-windows-x86_64.zip'
    $archiveHash = '94ca790a6e4992a58d22c1a45945fe0c3cfd31fbe93760fe3bb6bc26fec5b7c99d34660c1deb9861797d0b8e5f3d65607305b2d6f493f29d851b383add07ff99'
}
$archiveName = Split-Path $archiveUrl -Leaf
$archivePath = "$env:TEMP\$archiveName"

Write-Host 'Downloading Kibana...'
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA512).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}

Write-Host 'Installing Kibana...'
Get-ChocolateyUnzip -FileFullPath $archivePath -Destination $serviceHome
$archiveTempPath = Resolve-Path $serviceHome\kibana-*
Move-Item $archiveTempPath\* $serviceHome
Remove-Item $archiveTempPath
Remove-Item $archivePath

Write-Output "Installing the $serviceName service..."
nssm install $serviceName $serviceHome\bin\kibana.bat
nssm set $serviceName Start SERVICE_AUTO_START
nssm set $serviceName AppDirectory $serviceHome
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
@('optimize', 'data', 'logs') | ForEach-Object {
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

Write-Output "Starting the $serviceName service..."
Start-Service $serviceName

$apiBaseUrl = 'http://localhost:5601/api'

function Invoke-KibanaApi($relativeUrl, $body, $method='Post') {
    $url = "$apiBaseUrl/$relativeUrl"
    if ($method -eq 'Get') {
        if ($body) {
            # transform the body into a query string.
            $qs = @()
            $body.GetEnumerator() | ForEach-Object {
                $key = $_.Name
                if ($_.Value -isnot [Array]) {
                    $qs += "$([Uri]::EscapeDataString($key))=$([Uri]::EscapeDataString($_.Value))"
                } else {
                    $_.Value | ForEach-Object {
                        $qs += "$([Uri]::EscapeDataString($key))=$([Uri]::EscapeDataString($_))"
                    }
                }
            }
            if ($qs) {
                $url += "?$($qs -join '&')"
            }
        }
        $body = $null
    }
    Invoke-RestMethod `
        -Method $method `
        -Uri $url `
        -ContentType 'application/json' `
        -Headers @{
            'kbn-xsrf' = 'true'
        } `
        -Body (ConvertTo-Json -Depth 100 -Compress $body)
}

function Wait-ForKibanaReady {
    Wait-ForCondition {
        $response = Invoke-KibanaApi `
            core/capabilities `
            @{applications=@("kibana:discover")}
        $response.discover.show -eq $true
    }
}

Write-Host 'Waiting for Kibana to be ready...'
Wait-ForKibanaReady

# create index patterns.
@(
    'logstash-*'
    'winlogbeat-*'
) | ForEach-Object {
    $id = $_ -replace '(.+)-.*','$1'
    $title = $_
    Write-Host "Creating Kibana index-pattern $title..."
    $response = Invoke-KibanaApi "saved_objects/index-pattern/$id" @{
        attributes = @{
            title = $title
            timeFieldName = '@timestamp'
        }
    }
    Write-Host "Refreshing Kibana index-pattern $title..."
    # NB there is no documented way to refresh the index-pattern,
    #    so we'll do it like the UI does and hope for the best.
    # see https://github.com/elastic/kibana/issues/6498
    $response = Invoke-KibanaApi -method 'Get' 'index_patterns/_fields_for_wildcard' @{
        pattern = $title
        meta_fields = @('_source', '_id', '_type', '_index', '_score')
    }
    $response = Invoke-KibanaApi -method 'Put' "saved_objects/index-pattern/$id" @{
        attributes = @{
            title = $title
            timeFieldName = '@timestamp'
            fields = (ConvertTo-Json -Depth 100 -Compress $response.fields)
        }
    }
}
# list index patterns.
(Invoke-KibanaApi -method 'Get' 'saved_objects/_find?type=index-pattern&fields=id&fields=title&per_page=10000').saved_objects | ForEach-Object {
    Write-Host "Kibana Index Pattern $($_.id) $($_.attributes.title)"
}

# add default desktop shortcuts (called from a provision-base.ps1 generated script).
[IO.File]::WriteAllText(
    "$env:USERPROFILE\ConfigureDesktop-Kibana.ps1",
@'
[IO.File]::WriteAllText(
    "$env:USERPROFILE\Desktop\Kibana.url",
    @"
[InternetShortcut]
URL=http://localhost:5601
"@)
'@)
