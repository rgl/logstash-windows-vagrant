# install dependencies.
choco install -y adoptopenjdk11
choco install -y gradle --version 6.2.2

# update $env:PATH with the recently installed Chocolatey packages.
Import-Module C:\ProgramData\chocolatey\helpers\chocolateyInstaller.psm1
Update-SessionEnvironment
