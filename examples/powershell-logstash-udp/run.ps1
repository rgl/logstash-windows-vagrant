function Send-UdpDatagram {
    param (
        [string]$IpAddress,
        [int]$Port,
        [string]$Message
    )
    $address = [System.Net.IPAddress]::Parse($IpAddress)
    $endPoint = New-Object System.Net.IPEndPoint($address, $Port)
    $socket = New-Object System.Net.Sockets.Socket $endPoint.Address.AddressFamily,'Dgram','Udp'
    try {
        $encodedText = [Text.Encoding]::UTF8.GetBytes($Message)
        $socket.SendTo($encodedText, $endPoint) | Out-Null
    }
    finally {
        $socket.Close()
    }
}

$json = New-Object PSObject -Property @{
    '@timestamp' = Get-Date -Format o
    message = 'Hello World'
    application = 'powershell-logstash-udp/1.0'
} | ConvertTo-Json -Compress
Send-UdpDatagram '127.0.0.1' 9125 $json
