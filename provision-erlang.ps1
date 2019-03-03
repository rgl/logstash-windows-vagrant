choco install -y erlang
Write-Host 'Erlang OTP release version:'
erl -noshell -eval 'erlang:display(erlang:system_info(otp_release)), halt().'

choco install -y rebar3
Write-Host 'rebar3 version:'
rebar3 --version
