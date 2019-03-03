%%%-------------------------------------------------------------------
%% @doc example public API
%% @end
%%%-------------------------------------------------------------------

-module(example_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    % NB lager:info is only available when you add -compile([{parse_transform, lager_transform}]).
    %    to a module or {erl_opts, [{parse_transform, lager_transform}]}. to rebar.config.
    %    otherwise you have to use the generic lager api, e.g., lager:log(info, self(), "start"),
    lager:info("Begin"),
    TransactionId = uuid:to_string(simple, uuid:uuid4()),
    try
        A = 10,
        B = 0,
        lager:debug([{transactionId, TransactionId}], "Dividing ~p by ~p", [A, B]),
        io:format("~p~n", [A / B])
    catch
        Exception:Reason ->
            lager:error(
                [{transactionId, TransactionId}],
                "Something went wrong with the division~nStacktrace:~s",
                [lager:pr_stacktrace(erlang:get_stacktrace(), {Exception, Reason})])
    end,
    example_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    lager:info("End"),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
