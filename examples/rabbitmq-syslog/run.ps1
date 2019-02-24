Write-Host 'Listing the RabbitMQ connection properties...'
&"$env:TEMP\test-amqp.exe" -url 'amqp://guest:guest@localhost:5672'
