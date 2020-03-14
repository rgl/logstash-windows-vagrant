Write-Output 'Building the example...'
gradle clean build --warning-mode all

Write-Output 'Executing the example...'
java -jar build/libs/example-1.0.0-all.jar
