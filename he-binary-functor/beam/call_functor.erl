%% BEAM assembly – functor helpers for CallActor / OTP fibration
%% Generated style: erlc -S (register-based, TCO-ready)
%% ~250 lines

{module, call_functor}.
{exports, [{'apply_transform',2},
           {'sip_transition',2},
           {'rtp_update',2},
           {'worm_archive',1},
           {'fibre_reset',1},
           {'monoidal_product',2},
           {'natural_restart',1},
           {'mailbox_loop',1},
           {'module_info',0},
           {'module_info',1}]}.
{attributes, []}.
{labels, 48}.

%%----------------------------------------------------------------
%% apply_transform/2 (State, Message) -> NewState
%% Functorial mapping F(State) → NewState
%%----------------------------------------------------------------
{function, apply_transform, 2, 2}.
  {label,1}.
    {line,[{location,"call_functor.erl",42}]}.
    {func_info,{atom,call_functor},{atom,apply_transform},2}.
  {label,2}.
    {test,is_tuple,{f,6},[{x,1}]}.
    {test,is_eq_exact,{f,4},[{x,1},{atom,sip}]}.
    %% Message = {:sip, Event}
    {get_tuple_element,{x,1},1,{x,2}}.
    {move,{x,0},{x,1}}. %% State
    {move,{x,2},{x,0}}. %% Event
    {call_only,2,{f,10}}. %% sip_transition/2 (TCO)
  {label,4}.
    {test,is_eq_exact,{f,6},[{x,1},{atom,rtp}]}.
    %% Message = {:rtp, Packet}
    {get_tuple_element,{x,1},1,{x,2}}.
    {move,{x,0},{x,1}}.
    {move,{x,2},{x,0}}.
    {call_only,2,{f,18}}. %% rtp_update/2 (TCO)
  {label,6}.
    %% Unknown message – identity
    {move,{x,0},{x,0}}.
    return.

%%----------------------------------------------------------------
%% sip_transition/2 (Event, State) -> NewState
%% Discrete topological control-flow parser
%%----------------------------------------------------------------
{function, sip_transition, 2, 10}.
  {label,9}.
    {line,[{location,"call_functor.erl",61}]}.
    {func_info,{atom,call_functor},{atom,sip_transition},2}.
  {label,10}.
    %% State is a map; extract :sip key
    {test,is_map,{f,16},[{x,1}]}.
    {get_map_elements,{f,16},{x,1},{x,2},[{\{atom,sip\},{x,3}}]}.
    %% x3 = current SIP state atom
    {select_val,{x,3},
                {f,16},
                {list,[{atom,init},{f,11},
                       {atom,trying},{f,12},
                       {atom,invited},{f,13},
                       {atom,active},{f,14},
                       {atom,terminated},{f,15}]}}.
  {label,11}. %% :init
    {test,is_eq_exact,{f,16},[{x,0},{atom,invite}]}.
    {move,{atom,trying},{x,4}}.
    {jump,{f,17}}.
  {label,12}. %% :trying
    {test,is_eq_exact,{f,16},[{x,0},{atom,ringing}]}.
    {move,{atom,invited},{x,4}}.
    {jump,{f,17}}.
  {label,13}. %% :invited
    {test,is_eq_exact,{f,16},[{x,0},{atom,answer}]}.
    {move,{atom,active},{x,4}}.
    {jump,{f,17}}.
  {label,14}. %% :active
    {test,is_eq_exact,{f,16},[{x,0},{atom,bye}]}.
    {move,{atom,terminated},{x,4}}.
    {jump,{f,17}}.
  {label,15}. %% :terminated – absorb
    {move,{x,3},{x,4}}.
    {jump,{f,17}}.
  {label,16}. %% illegal / unknown – identity
    {move,{x,3},{x,4}}.
  {label,17}.
    %% put_map_assoc :sip => new_state
    {put_map_assoc,{f,16},{x,1},{x,0},1,[{\{atom,sip\},{x,4}}]}.
    return.

%%----------------------------------------------------------------
%% rtp_update/2 (Packet, State) -> NewState
%% Continuous-time stream amplitude mapper
%%----------------------------------------------------------------
{function, rtp_update, 2, 18}.
  {label,17}.
    {line,[{location,"call_functor.erl",98}]}.
    {func_info,{atom,call_functor},{atom,rtp_update},2}.
  {label,18}.
    {test,is_map,{f,24},[{x,1}]}.
    {get_map_elements,{f,24},{x,1},{x,2},
     [{\{atom,rtp\},{x,3}},{\{atom,sequence\},{x,4}}]}.
    %% Packet must be a map with seq / ts / ssrc
    {test,is_map,{f,24},[{x,0}]}.
    {get_map_elements,{f,24},{x,0},{x,5},
     [{\{atom,seq\},{x,6}},{\{atom,ts\},{x,7}},{\{atom,ssrc\},{x,8}}]}.
    %% sequence + 1
    {gc_bif,'+',{f,24},4,[{x,4},{integer,1}],{x,9}}.
    %% simplified jitter: | (ts - last_ts) - (seq - old_seq) |
    {get_map_elements,{f,24},{x,3},{x,10},[{\{atom,last_ts\},{x,11}}]}.
    {test,is_eq_exact,{f,20},[{x,11},{integer,0}]}.
    {move,{float,0.0},{x,12}}. %% first packet
    {jump,{f,21}}.
  {label,20}.
    {gc_bif,'-',{f,24},5,[{x,7},{x,11}],{x,13}}.
    {gc_bif,'-',{f,24},6,[{x,6},{x,4}],{x,14}}.
    {gc_bif,'-',{f,24},7,[{x,13},{x,14}],{x,15}}.
    {gc_bif,abs,{f,24},1,[{x,15}],{x,16}}.
    {get_map_elements,{f,24},{x,3},{x,17},[{\{atom,jitter\},{x,18}}]}.
    {gc_bif,'-',{f,24},3,[{x,16},{x,18}],{x,19}}.
    {gc_bif,'/',{f,24},2,[{x,19},{integer,16}],{x,20}}.
    {gc_bif,'+',{f,24},2,[{x,18},{x,20}],{x,12}}.
  {label,21}.
    %% rebuild rtp map
    {put_map_assoc,{f,24},{x,3},{x,21},4,
     [{\{atom,ssrc\},{x,8}},
      {\{atom,seq\},{x,6}},
      {\{atom,last_ts\},{x,7}},
      {\{atom,jitter\},{x,12}}]}.
    %% put back into state
    {put_map_assoc,{f,24},{x,1},{x,0},2,
     [{\{atom,rtp\},{x,21}},{\{atom,sequence\},{x,9}}]}.
    return.
  {label,24}.
    %% bad packet – identity
    {move,{x,1},{x,0}}.
    return.

%%----------------------------------------------------------------
%% worm_archive/1 (State) -> ok
%% Immutable append before fibre restart
%%----------------------------------------------------------------
{function, worm_archive, 1, 26}.
  {label,25}.
    {line,[{location,"call_functor.erl",142}]}.
    {func_info,{atom,call_functor},{atom,worm_archive},1}.
  {label,26}.
    {allocate,1,1}.
    {move,{x,0},{y,0}}.
    %% Build archive tuple
    {test_heap,6,1}.
    {put_tuple_arity,5,{x,0}}.
    {put,{atom,worm}}.
    {put,{y,0}}. %% full state
    {put,{bif,system_time,1,[{atom,millisecond}],{x,1}}}.
    {put,{atom,archived}}.
    {put,{atom,ok}}.
    %% In real system: memory-mapped append
    {move,{x,0},{x,0}}.
    {call_ext,1,{extfunc,logger,info,1}}.
    {deallocate,1}.
    {move,{atom,ok},{x,0}}.
    return.

%%----------------------------------------------------------------
%% fibre_reset/1 (OldState) -> FreshState
%% Natural transformation component η_c
%%----------------------------------------------------------------
{function, fibre_reset, 1, 28}.
  {label,27}.
    {line,[{location,"call_functor.erl",161}]}.
    {func_info,{atom,call_functor},{atom,fibre_reset},1}.
  {label,28}.
    %% Keep only identity fields; wipe SIP/RTP
    {test,is_map,{f,30},[{x,0}]}.
    {get_map_elements,{f,30},{x,0},{x,1},[{\{atom,id\},{x,2}}]}.
    {put_map_assoc,{f,30},{literal,#{}},{x,0},3,
     [{\{atom,id\},{x,2}},
      {\{atom,sip\},{atom,init}},
      {\{atom,rtp\},{literal,#{ssrc=>0,seq=>0,jitter=>0.0,codec=>pcmu,last_ts=>0}}},
      {\{atom,sequence\},{integer,0}}]}.
    return.
  {label,30}.
    {move,{literal,#{sip=>init,sequence=>0}},{x,0}}.
    return.

%%----------------------------------------------------------------
%% monoidal_product/2 (SipState, RtpState) -> Product
%% S_SIP ⊗ S_RTP
%%----------------------------------------------------------------
{function, monoidal_product, 2, 32}.
  {label,31}.
    {line,[{location,"call_functor.erl",178}]}.
    {func_info,{atom,call_functor},{atom,monoidal_product},2}.
  {label,32}.
    {test_heap,4,2}.
    {put_tuple_arity,3,{x,2}}.
    {put,{atom,product}}.
    {put,{x,0}}.
    {put,{x,1}}.
    {move,{x,2},{x,0}}.
    return.

%%----------------------------------------------------------------
%% natural_restart/1 (FailedPid) -> ok
%% Supervisor-side natural transformation
%%----------------------------------------------------------------
{function, natural_restart, 1, 34}.
  {label,33}.
    {line,[{location,"call_functor.erl",189}]}.
    {func_info,{atom,call_functor},{atom,natural_restart},1}.
  {label,34}.
    {allocate,1,1}.
    {move,{x,0},{y,0}}.
    %% Archive first (WORM)
    {call,1,{f,26}}. %% worm_archive/1
    %% Then reset fibre
    {move,{y,0},{x,0}}.
    {call,1,{f,28}}. %% fibre_reset/1
    {deallocate,1}.
    {move,{atom,ok},{x,0}}.
    return.

%%----------------------------------------------------------------
%% mailbox_loop/1 (State) -> no_return
%% Infinite TCO receive loop (GenServer core)
%%----------------------------------------------------------------
{function, mailbox_loop, 1, 36}.
  {label,35}.
    {line,[{location,"call_functor.erl",205}]}.
    {func_info,{atom,call_functor},{atom,mailbox_loop},1}.
  {label,36}.
    {loop_rec,{f,40},{x,1}}. %% wait for message
    {test,is_tuple,{f,39},[{x,1}]}.
    {test,is_eq_exact,{f,39},[{x,1},{atom,transition}]}.
    {get_tuple_element,{x,1},1,{x,2}}. %% payload
    {remove_message}.
    %% apply_transform(State, Msg)
    {move,{x,0},{x,1}}.
    {move,{x,2},{x,0}}.
    {call,2,{f,2}}. %% apply_transform/2
    %% Tail jump – constant stack
    {jump,{f,36}}.
  {label,39}.
    {remove_message}. %% drop unknown
    {jump,{f,36}}.
  {label,40}.
    {wait,{f,36}}. %% empty mailbox – suspend

%%----------------------------------------------------------------
%% module_info
%%----------------------------------------------------------------
{function, module_info, 0, 42}.
  {label,41}.
    {line,[]}.
    {func_info,{atom,call_functor},{atom,module_info},0}.
  {label,42}.
    {move,{atom,call_functor},{x,0}}.
    {call_ext_only,1,{extfunc,erlang,get_module_info,1}}.

{function, module_info, 1, 44}.
  {label,43}.
    {line,[]}.
    {func_info,{atom,call_functor},{atom,module_info},1}.
  {label,44}.
    {move,{x,0},{x,1}}.
    {move,{atom,call_functor},{x,0}}.
    {call_ext_only,2,{extfunc,erlang,get_module_info,2}}.

%% End of module – total instruction lines ≈ 248
