# make sure this builds and runs from a non-network path as erlang build machinery
# depends on things that are only available on NTFS (e.g. symlinks).
if ($PWD.Path -like 'C:\vagrant\*') {
    Copy-Item -Recurse $PWD C:\Windows\TEMP
    cd "C:\Windows\TEMP\$(Split-Path -Leaf $PWD)"
    .\run.ps1
    Exit 0
}

Write-Host 'Compiling application...'
rebar3 as prod release

Write-Host 'Running application...'
# to be able to run the application has a regular cli appliaction patch the
# generated boot script to use erl.exe instead of werl.exe.
# see https://github.com/erlang/rebar3/issues/2026
Set-Content -Encoding ascii -Path _build\prod\rel\example\bin\example.cmd -Value (
    (Get-Content _build\prod\rel\example\bin\example.cmd) `
        -replace 'werl\.exe','erl.exe' `
        -replace '@start "%rel_name% console" %werl%','@%werl%'
)
.\_build\prod\rel\example\bin\example.cmd console
