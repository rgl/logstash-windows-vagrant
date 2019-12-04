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
    $archiveUrl = 'https://artifacts.elastic.co/downloads/kibana/kibana-oss-7.5.0-windows-x86_64.zip'
    $archiveHash = '02986b5a2ada813f8fbbdb2f45e13e512957b667e753db70bdd52887a8f173a7d0953b44f6b0472a4da67d86ecec649663a81e33b53c4ffad0a6db3bec3b261d'
} else {
    # see https://www.elastic.co/downloads/kibana
    $archiveUrl = 'https://artifacts.elastic.co/downloads/kibana/kibana-7.5.0-windows-x86_64.zip'
    $archiveHash = '77b901c6b3a3e29a5c3f5c8da5d995393f737c2f84e197778f4b86c995d22564327ae2e0ca142f9b874b90d6a519fe273af04e01626ae42549c8105bdef5eea2'
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
            'kbn-xsrf' = 'provision'
        } `
        -Body (ConvertTo-Json -Depth 100 -Compress $body)
}

function Wait-ForKibanaReady {
    Wait-ForCondition {
        $response = Invoke-RestMethod `
            -Method Get `
            -Uri $apiBaseUrl/features
        $response.app[0] -eq 'kibana'
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
