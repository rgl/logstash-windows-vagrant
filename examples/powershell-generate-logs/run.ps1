# generate logs in the serilog format and send them to logstash http endpoint.

$batches = 5
$batchSize = 10
$logstashUrl = 'http://127.0.0.1:8080/serilog'

$n = 0
$timestamp = Get-Date
for ($batch = 0; $batch -lt $batches; ++$batch) {
    Write-Host "Sending batch #$batch..."
    $events = @()
    for ($i = 0; $i -lt $batchSize; ++$i) {
        $events += New-Object PSObject -Property @{
            Timestamp = $timestamp.ToString('O')
            Level = 'Information'
            MessageTemplate = 'Example'
            RenderedMessage = 'Example'
            Properties = @{
                SourceContext = 'run'
                Application = "powershell-generate-logs$($n % 4 + 1)/1.0"
            }
        }
        ++$n
    }
    $data = New-Object PSObject -Property @{
        events = $events
    }
    Invoke-RestMethod `
        -Method Post `
        -Uri $logstashUrl `
        -ContentType 'application/json' `
        -Body (ConvertTo-Json -Compress -Depth 100 $data)
    $timestamp = $timestamp.AddMilliseconds(500)
}
