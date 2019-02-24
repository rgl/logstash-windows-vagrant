$serviceName = 'rabbitmq'

choco install -y rabbitmq --version 3.7.7

Write-Host "Stopping the $serviceName service..."
Stop-Service $serviceName

# see https://www.rabbitmq.com/configure.html#config-location
# see https://www.rabbitmq.com/logging.html#logging-to-syslog
Write-Host "Configuring the $serviceName service..."
Set-Content `
    -Encoding ascii `
    -Path "$env:APPDATA\RabbitMQ\rabbitmq.conf" `
    -Value @'
# log to syslog.
log.syslog = true
log.syslog.ip = 127.0.0.1
log.syslog.port = 514
log.syslog.transport = udp
log.syslog.protocol = rfc3164
'@

Write-Output "Starting the $serviceName service..."
Start-Service $serviceName

# install a tool to test amqp connections.
$archiveUrl = 'https://github.com/rgl/test-amqp/releases/download/v0.0.1/test-amqp.zip'
$archiveHash = '954e10f229fad54989f8cb489d8ad47056bb6d5727175c6a04072193a1b80b21'
$archiveName = Split-Path -Leaf $archiveUrl
$archivePath = "$env:TEMP\$archiveName"
Write-Host "Downloading $archiveName..."
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}
Write-Host "Installing $archiveName..."
Expand-Archive $archivePath -DestinationPath $env:TEMP
Remove-Item $archivePath

# wait for RabbitMQ to start.
while ($true) {
    $result = &"$env:TEMP\test-amqp.exe" -url 'amqp://localhost:5672'
    if ($result -notlike '*Failed to connect to RabbitMQ*') {
        break
    }
    Start-Sleep -Seconds 1
}
