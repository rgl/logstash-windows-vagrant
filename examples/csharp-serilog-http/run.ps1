Write-Host 'Publishing the logs to logstash...'
dotnet run

Write-Host 'Open C:\logstash\logs\logstash-stdout.log to see the logs'
Write-Host '  e.g. Get-Content -Tail 80 C:\logstash\logs\logstash-stdout.log'
