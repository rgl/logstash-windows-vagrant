Create an example application:

```bash
rebar3 new release example
cd example
```

Configure the rebar project to depend on the lager package by modifying `rebar.config` with:

```erlang
{deps, [lager, lager_logstash]}.
```

Configure the erlang compiler to automatically apply the lager transformations by modifying `rebar.config` with:

```erlang
{erl_opts, [
  {parse_transform, lager_transform},
  ...
]}.
```

Configure the lager to log to the console and logstash by modifying `config/sys.config` with:

```erlang
[
  ...
  {lager, [
    {handlers, [
      {lager_console_backend, [{level, info}]},
      {lager_logstash_backend, [
        {host, "localhost"},
        {port, 9125},
        {fields, [
          {application, <<"erlang-lager-logstash-udp/1.0">>}
        ]}
      ]}
    ]}
  ]}
].
```

Configure the application to depend on the `lager` application by modifying `apps/example/src/example_app.src`:

```erlang
{application, example, [
  ...
  {applications, [
    ...,
    lager
  ]},
```

Use the lager to log the application startup by modifying `apps/example/src/example_app.erl`:

```erlang
start(_StartType, _StartArgs) ->
    % NB lager:info is only available when you add -compile([{parse_transform, lager_transform}]).
    %    to a module or {erl_opts, [{parse_transform, lager_transform}]}. to rebar.config.
    %    otherwise you have to use the generic lager api, e.g., lager:log(info, self(), "start"),
    lager:info("start"),
    example_sup:start_link().
```

Start the application on the shell:

```bash
rebar3 shell
```

Then stop it:

```erlang
init:stop().
```
