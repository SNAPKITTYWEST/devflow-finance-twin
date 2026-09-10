% funnel_backend.pl
% Minimal dispatch: parse JSON (assumes JSON already parsed into Prolog terms)
% For PRPG integration, the transport layer should call dispatch_op/3 with
% Op (atom), Payload (dict or term), and get ResultJson (string).

:- module(funnel_backend, [dispatch_op/3]).

dispatch_op(return_item, Payload, ResultJson) :-
    % Payload expected: payload{company: C, batch: B, entry: E, reason: R}
    ( get_dict(company, Payload, C) -> true ; C = '' ),
    ( get_dict(batch, Payload, B) -> true ; B = '' ),
    ( get_dict(entry, Payload, E) -> true ; E = '' ),
    ( get_dict(reason, Payload, R) -> true ; R = '' ),
    % Simulate lookup and state transition
    % In production, query DB or call COBOL/RPG posting service
    ( C \= '' ->
        Result = _{status:ok, new_seq:"000001234"}
    ;
        Result = _{status:error, error:"NOTFOUND"}
    ),
    % Convert Result dict to JSON string (assumes library)
    with_output_to(string(ResultJson), json_write_dict(current_output, Result)).
