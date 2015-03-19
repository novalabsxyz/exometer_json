%% -------------------------------------------------------------------
%% Copyright (C) 2015 Helium Systems Inc.
%%
%% This software may be modified and distributed under the terms
%% of the MIT license.  See the LICENSE file for details.
%%
%% -------------------------------------------------------------------

%% @doc Custom reporting probe for pushing JSON payloads to a sink URL
%%
%% All data subscribed to by the plugin (through exometer_report:subscribe())
%% will be sent to the sink using an HTTP request. The default request type is
%% PUT, but can be overridden by the `json_http_request_type' configuration option.
%%
%% Options:
%%
%% `{json_sink_url, binary()}' - Host and port of the JSON sink
%% Default: <<"http://localhost:8000">>
%%
%% `{json_http_request_type, atom()}` - HTTP request type to use to
%% forward data to the sink. Valid values are `put' and `post' Default
%% value is `put'.
%%
%% @end

-module(exometer_report_json).
-behaviour(exometer_report).
-author("Kelly McLaughlin <kelly@helium.com>").

%% gen_server callbacks
-export(
   [
    exometer_init/1,
    exometer_info/2,
    exometer_cast/2,
    exometer_call/3,
    exometer_report/5,
    exometer_subscribe/5,
    exometer_unsubscribe/4,
    exometer_newentry/2,
    exometer_setopts/4,
    exometer_terminate/2
   ]).

-include("log.hrl").

-define(DEFAULT_SINK_URL, <<"http://localhost:8000">>).
-define(DEFAULT_REQUEST_TYPE, put).

-record(state, {sink_url :: binary(),
                request_type :: request_type(),
                hostname :: string()}).
-type state() :: #state{}.

-type options() :: [{atom(), any()}].
-type request_type() :: put | post.
-type value() :: any().

%% calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}).
-define(UNIX_EPOCH, 62167219200).

%% Probe callbacks

-spec exometer_init(options()) -> {ok, state()}.
exometer_init(Opts) ->
    SinkUrl = get_opt(json_sink_url, Opts, ?DEFAULT_SINK_URL),
    HttpRequestType = get_and_validate_request_type(Opts),
    HostName = check_hostname(get_opt(hostname, Opts, "auto")),
    State = #state{sink_url=SinkUrl,
                   request_type=HttpRequestType,
                   hostname=HostName},
    {ok, State}.

-spec exometer_report(exometer_report:metric(),
                      exometer_report:datapoint(),
                      exometer_report:extra(),
                      value(),
                      state()) -> {ok, state()} | {error, term()}.
exometer_report(Metric, DataPoint, _Extra, Value, State) ->
    Data = {
      [
       {<<"type">>, <<"exometer_metric">>},
       {<<"body">>, {[
                      {<<"name">>, name(Metric)},
                      {<<"value">>, Value},
                      {<<"timestamp">>, unix_time()},
                      {<<"host">>, iolist_to_binary(State#state.hostname)},
                      {<<"instance">>, DataPoint}
                     ]}
       }
      ]
     },

    Payload = jsx:encode(Data),

    case send_to_sink(Payload, State) of
        {ok, State} ->
            {ok, State};
        {error, _}=Error ->
            Error
    end.

-spec send_to_sink(binary(), state()) -> {ok, state()} | {error, term()}.
send_to_sink(Payload, State) ->
    #state{sink_url=SinkUrl,
           request_type=RequestType} = State,
    Headers = [{<<"content-type">>, <<"application/json">>}],
    Options = [],
    case hackney:RequestType(SinkUrl, Headers, Payload, Options) of
        {ok, StatusCode, _RespHeaders, _ClientRef} ->
            ?info("Sink return status code: ~b", [StatusCode]),
            {ok, State};
        {error, Reason}=Error ->
            ?error("Sink returned error: ~p", [Reason]),
            Error
    end.

exometer_subscribe(_Metric, _DataPoint, _Extra, _Interval, State) ->
    {ok, State}.

exometer_unsubscribe(_Metric, _DataPoint, _Extra, State) ->
    {ok, State}.

exometer_call(Unknown, From, State) ->
    ?info("Unknown call ~p from ~p", [Unknown, From]),
    {ok, State}.

exometer_cast(Unknown, State) ->
    ?info("Unknown cast: ~p", [Unknown]),
    {ok, State}.

exometer_info(Unknown, State) ->
    ?info("Unknown info: ~p", [Unknown]),
    {ok, State}.

exometer_newentry(_Entry, State) ->
    {ok, State}.

exometer_setopts(_Metric, _Options, _Status, State) ->
    {ok, State}.

exometer_terminate(_, _) ->
    ignore.

unix_time() ->
    datetime_to_unix_time(erlang:universaltime()).

datetime_to_unix_time({{_,_,_},{_,_,_}} = DateTime) ->
    calendar:datetime_to_gregorian_seconds(DateTime) - ?UNIX_EPOCH.

get_opt(K, Opts, Default) ->
    exometer_util:get_opt(K, Opts, Default).

-spec check_hostname(string()) -> string().
check_hostname("auto") ->
    net_adm:localhost();
check_hostname(H) ->
    H.

name(Metric) ->
    iolist_to_binary(metric_to_string(Metric)).

metric_to_string([Final]) ->
    metric_elem_to_list(Final);

metric_to_string([H | T]) ->
    metric_elem_to_list(H) ++ "_" ++ metric_to_string(T).

metric_elem_to_list(E) when is_atom(E) ->
    atom_to_list(E);

metric_elem_to_list(E) when is_list(E) ->
    E;

metric_elem_to_list(E) when is_integer(E) ->
    integer_to_list(E).

-spec get_and_validate_request_type(options()) -> request_type().
get_and_validate_request_type(Opts) ->
    validate_request_type(get_opt(json_http_request_type,
                                  Opts,
                                  ?DEFAULT_REQUEST_TYPE)).

-spec validate_request_type(atom()) -> request_type().
validate_request_type(put) ->
    put;
validate_request_type(post) ->
    post;
validate_request_type(_) ->
    put.
