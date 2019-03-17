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
    % send a message from the erlang error_logger to test if lager is handling that logger.
    error_logger:info_msg("A test message from the ~p module sent from the erlang error_logger", [?MODULE]),
    TransactionId = uuid:to_string(simple, uuid:uuid4()),
    try
        A = 10,
        B = 0,
        lager:debug([{transactionId, TransactionId}], "Dividing ~p by ~p", [A, B]),
        io:format("~p~n", [A / B])
    catch
        Class:Reason:Stacktrace ->
            lager:error(
                [{transactionId, TransactionId}],
                "Something went wrong with the division~nStacktrace:~s",
                [lager:pr_stacktrace(Stacktrace, {Class, Reason})])
    end,
    % since this is an example application that is suppossed to terminate after using
    % the logger, we do just that after 5000 milliseconds.
    timer:apply_after(5000, init, stop, []),
    example_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    lager:info("End"),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
