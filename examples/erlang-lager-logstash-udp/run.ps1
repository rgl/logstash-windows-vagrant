Write-Host 'Compiling application...'
rebar3 as prod escriptize

Write-Host 'Application contents:'
7z l _build\prod\bin\example # or tar tf _build\prod\bin\example

Write-Host 'Running application...'
escript _build\prod\bin\example
