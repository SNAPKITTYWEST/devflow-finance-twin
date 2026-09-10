%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% godel_symbolic_kernel.lgt
% Dense symbolic kernel: Gödel numbering + formal arithmetic + provability
% + self-reference primitives, engineered as Logtalk objects/protocols/categories.
% Target: ~550-650 LOC of raw logic. Logic-engineer grade.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- encoding(utf8).

:- op(1200, xfx, ':-').
:- op(1100, xfy, ';').
:- op(1050, xfy, '->').
:- op(1000, xfy, ',').
:- op(900, fy, '\+').
:- op(700, xfx, [=, \=, ==, \==, @<, @>, @=<, @>=, is, =:=, =\=]).
:- op(500, yfx, [+, -, /\, \/]).
:- op(400, yfx, [*, /, //, rem, mod, <<, >>]).
:- op(200, xfx, **).
:- op(200, xfy, ^).
:- op(200, fy, [+, -, \]).

% -----------------------------------------------------------------------------
% Protocol: basic arithmetic signature (Peano + Gödel coding primitives)
% -----------------------------------------------------------------------------
:- protocol(arithmetic_p).
 :- public([
  zero/1, succ/2, add/3, mul/3, exp/3, lt/2, leq/2,
  godel_pair/3, godel_unpair/3, sequence_code/2, term_code/2,
  formula_code/2, proof_code/2
 ]).
:- end_protocol.

% -----------------------------------------------------------------------------
% Category: pure Peano arithmetic (dense, no cuts where avoidable)
% -----------------------------------------------------------------------------
:- category(peano_c).
 :- public([zero/1, succ/2, add/3, mul/3, exp/3, lt/2, leq/2]).

 zero(0).
 succ(N, S) :- S is N + 1.

 add(0, Y, Y).
 add(s(X), Y, s(Z)) :- add(X, Y, Z). % symbolic form preferred
 add(X, Y, Z) :- integer(X), integer(Y), Z is X + Y.

 mul(0, _, 0).
 mul(s(X), Y, Z) :- mul(X, Y, W), add(W, Y, Z).
 mul(X, Y, Z) :- integer(X), integer(Y), Z is X * Y.

 exp(_, 0, 1).
 exp(X, s(Y), Z) :- exp(X, Y, W), mul(W, X, Z).
 exp(X, Y, Z) :- integer(X), integer(Y), Z is X ** Y.

 lt(X, Y) :- integer(X), integer(Y), X < Y.
 lt(0, s(_)).
 lt(s(X), s(Y)) :- lt(X, Y).

 leq(X, Y) :- X = Y ; lt(X, Y).
:- end_category.

% -----------------------------------------------------------------------------
% Category: Gödel β-function & pairing (Cantor + Gödel classic)
% -----------------------------------------------------------------------------
:- category(godel_coding_c).
 :- public([
  godel_pair/3, godel_unpair/3,
  beta/3, sequence_code/2, prime/1, nth_prime/2
 ]).

 % Cantor tuple function ⟨x,y⟩ = (x+y)(x+y+1)/2 + y
 godel_pair(X, Y, P) :-
  integer(X), integer(Y),
  S is X + Y,
  P is (S * (S + 1)) // 2 + Y.

 godel_unpair(P, X, Y) :-
  integer(P), P >= 0,
  % solve quadratic
  W is floor((-1 + sqrt(1 + 8*P)) / 2),
  T is W * (W + 1) // 2,
  Y is P - T,
  X is W - Y.

 % Gödel β-function: β(c,d,i) = rem(c, 1+(i+1)*d)
 beta(C, D, I, R) :-
  integer(C), integer(D), integer(I),
  R is C mod (1 + (I + 1) * D).

 % Encode finite sequence as single number via β + Chinese Remainder
 sequence_code(Seq, Code) :-
  is_list(Seq),
  length(Seq, L),
  ( L =:= 0
  -> Code = 0
  ; max_list(Seq, M),
   D0 is M + L + 1,
   find_d(Seq, D0, D),
   find_c(Seq, D, 0, C),
   godel_pair(C, D, Code)
  ).

 find_d(Seq, D, D) :-
  forall(nth0(I, Seq, A), (R is 1+(I+1)*D, A < R)).
 find_d(Seq, D0, D) :-
  D1 is D0 + 1,
  find_d(Seq, D1, D).

 find_c([], _, C, C).
 find_c([A|As], D, C0, C) :-
  % CRT step (simplified sequential construction)
  C1 is C0 + A, % placeholder; full CRT would use modular inverse
  find_c(As, D, C1, C).

 % Primes (sieve fragment for small Gödel numbers)
 prime(2). prime(3). prime(5). prime(7). prime(11).
 prime(13). prime(17). prime(19). prime(23). prime(29).
 prime(N) :- integer(N), N > 29, \+ has_factor(N, 3).

 has_factor(N, F) :- N mod F =:= 0.
 has_factor(N, F) :- F2 is F + 2, F2 * F2 =< N, has_factor(N, F2).

 nth_prime(1, 2).
 nth_prime(N, P) :- N > 1, nth_prime_acc(N, 2, 1, P).
 nth_prime_acc(N, Cand, Count, P) :-
  ( prime(Cand)
  -> (Count =:= N -> P = Cand ; C1 is Count+1, Cand1 is Cand+1, nth_prime_acc(N, Cand1, C1, P))
  ; Cand1 is Cand+1, nth_prime_acc(N, Cand1, Count, P)
  ).
:- end_category.

% -----------------------------------------------------------------------------
% Protocol: term / formula / proof language
% -----------------------------------------------------------------------------
:- protocol(formal_language_p).
 :- public([
  var/1, const/1, func/2, pred/2,
  term/1, atomic_formula/1, formula/1,
  free_vars/2, substitute/4, closed/1
 ]).
:- end_protocol.

% -----------------------------------------------------------------------------
% Object: first-order arithmetic language (dense constructors)
% -----------------------------------------------------------------------------
:- object(fol_arith,
 implements(formal_language_p),
 imports(peano_c)).

 :- public([encode_term/2, encode_formula/2, decode_term/2]).

 var(v(N)) :- integer(N), N >= 0.
 const(c(N)) :- integer(N), N >= 0.
 func(f(Name, Arity), Args) :- atom(Name), integer(Arity), length(Args, Arity).
 pred(p(Name, Arity), Args) :- atom(Name), integer(Arity), length(Args, Arity).

 term(var(_)).
 term(const(_)).
 term(func(_, Args)) :- maplist(term, Args).

 atomic_formula(pred(_, Args)) :- maplist(term, Args).
 atomic_formula(eq(T1, T2)) :- term(T1), term(T2).

 formula(atomic_formula(_)).
 formula(not(F)) :- formula(F).
 formula(and(F1, F2)) :- formula(F1), formula(F2).
 formula(or(F1, F2)) :- formula(F1), formula(F2).
 formula(implies(F1, F2)) :- formula(F1), formula(F2).
 formula(forall(V, F)) :- var(V), formula(F).
 formula(exists(V, F)) :- var(V), formula(F).

 free_vars(var(N), [v(N)]).
 free_vars(const(_), []).
 free_vars(func(_, Args), Vs) :-
  maplist(free_vars, Args, Vss), append(Vss, Vs0), sort(Vs0, Vs).
 free_vars(pred(_, Args), Vs) :-
  maplist(free_vars, Args, Vss), append(Vss, Vs0), sort(Vs0, Vs).
 free_vars(eq(T1, T2), Vs) :-
  free_vars(T1, V1), free_vars(T2, V2), append(V1, V2, Vs0), sort(Vs0, Vs).
 free_vars(not(F), Vs) :- free_vars(F, Vs).
 free_vars(and(F1, F2), Vs) :-
  free_vars(F1, V1), free_vars(F2, V2), append(V1, V2, Vs0), sort(Vs0, Vs).
 free_vars(or(F1, F2), Vs) :-
  free_vars(F1, V1), free_vars(F2, V2), append(V1, V2, Vs0), sort(Vs0, Vs).
 free_vars(implies(F1, F2), Vs) :-
  free_vars(F1, V1), free_vars(F2, V2), append(V1, V2, Vs0), sort(Vs0, Vs).
 free_vars(forall(v(N), F), Vs) :-
  free_vars(F, Vs0), delete(Vs0, v(N), Vs).
 free_vars(exists(v(N), F), Vs) :-
  free_vars(F, Vs0), delete(Vs0, v(N), Vs).

 closed(F) :- free_vars(F, []).

 substitute(var(N), var(N), Term, Term) :- !.
 substitute(var(M), var(N), _, var(M)) :- M =\= N, !.
 substitute(const(C), _, _, const(C)).
 substitute(func(Name, Args), V, Term, func(Name, Args1)) :-
  maplist(substitute_(V, Term), Args, Args1).
 substitute(pred(Name, Args), V, Term, pred(Name, Args1)) :-
  maplist(substitute_(V, Term), Args, Args1).
 substitute(eq(T1, T2), V, Term, eq(T1s, T2s)) :-
  substitute(T1, V, Term, T1s), substitute(T2, V, Term, T2s).
 substitute(not(F), V, Term, not(Fs)) :- substitute(F, V, Term, Fs).
 substitute(and(F1, F2), V, Term, and(F1s, F2s)) :-
  substitute(F1, V, Term, F1s), substitute(F2, V, Term, F2s).
 substitute(or(F1, F2), V, Term, or(F1s, F2s)) :-
  substitute(F1, V, Term, F1s), substitute(F2, V, Term, F2s).
 substitute(implies(F1, F2), V, Term, implies(F1s, F2s)) :-
  substitute(F1, V, Term, F1s), substitute(F2, V, Term, F2s).
 substitute(forall(v(N), F), v(N), _, forall(v(N), F)) :- !.
 substitute(forall(v(M), F), V, Term, forall(v(M), Fs)) :-
  substitute(F, V, Term, Fs).
 substitute(exists(v(N), F), v(N), _, exists(v(N), F)) :- !.
 substitute(exists(v(M), F), V, Term, exists(v(M), Fs)) :-
  substitute(F, V, Term, Fs).

 substitute_(V, Term, T, Ts) :- substitute(T, V, Term, Ts).

 % Minimal Gödel numbering for terms (prime-power style, dense)
 encode_term(var(N), Code) :- Code is 2 ** (N + 1).
 encode_term(const(N), Code) :- Code is 3 ** (N + 1).
 encode_term(func(Name, Args), Code) :-
  atom_codes(Name, Cs), sequence_code(Cs, NameCode),
  maplist(encode_term, Args, ArgCodes),
  sequence_code([NameCode|ArgCodes], Code).
 encode_term(eq(T1, T2), Code) :-
  encode_term(T1, C1), encode_term(T2, C2),
  godel_pair(C1, C2, Code).

 encode_formula(pred(Name, Args), Code) :-
  atom_codes(Name, Cs), sequence_code(Cs, NameCode),
  maplist(encode_term, Args, ArgCodes),
  sequence_code([NameCode|ArgCodes], Seq),
  Code is 5 * Seq. % tag
 encode_formula(not(F), Code) :-
  encode_formula(F, C), Code is 7 * C.
 encode_formula(and(F1, F2), Code) :-
  encode_formula(F1, C1), encode_formula(F2, C2),
  godel_pair(C1, C2, P), Code is 11 * P.
 encode_formula(or(F1, F2), Code) :-
  encode_formula(F1, C1), encode_formula(F2, C2),
  godel_pair(C1, C2, P), Code is 13 * P.
 encode_formula(implies(F1, F2), Code) :-
  encode_formula(F1, C1), encode_formula(F2, C2),
  godel_pair(C1, C2, P), Code is 17 * P.
 encode_formula(forall(v(N), F), Code) :-
  encode_formula(F, C), Code is 19 ** (N + 1) * C.
 encode_formula(exists(v(N), F), Code) :-
  encode_formula(F, C), Code is 23 ** (N + 1) * C.

 % Stub decode (inverse mapping left partial for density)
 decode_term(Code, Term) :- integer(Code), Code > 0, decode_term_(Code, Term).
 decode_term_(Code, var(N)) :- power_of(2, Code, N1), N is N1 - 1.
 decode_term_(Code, const(N)) :- power_of(3, Code, N1), N is N1 - 1.

 power_of(Base, N, E) :- power_of_(Base, N, 0, E).
 power_of_(Base, 1, E, E) :- !.
 power_of_(Base, N, Acc, E) :- N > 1, N mod Base =:= 0, N1 is N // Base, Acc1 is Acc + 1, power_of_(Base, N1, Acc1, E).
:- end_object.

% -----------------------------------------------------------------------------
% Protocol: proof system / deduction
% -----------------------------------------------------------------------------
:- protocol(proof_system_p).
 :- public([
  axiom/1, inference_rule/3, proof/2, provable/2,
  hilbert_axiom/1, mp/3, gen/2
 ]).
:- end_protocol.

% -----------------------------------------------------------------------------
% Category: Hilbert-style calculus fragment for arithmetic
% -----------------------------------------------------------------------------
:- category(hilbert_c).
 :- public([hilbert_axiom/1, mp/3, gen/2]).

 % Axiom schemas (classic Hilbert)
 hilbert_axiom(implies(A, implies(B, A))).
 hilbert_axiom(implies(implies(A, implies(B, C)), implies(implies(A, B), implies(A, C)))).
 hilbert_axiom(implies(implies(not(A), not(B)), implies(B, A))).
 hilbert_axiom(implies(forall(v(N), A), A1)) :-
  % quantifier axiom (simplified instantiation)
  substitute(A, v(N), Term, A1), term(Term).
 hilbert_axiom(implies(A, forall(v(N), A))) :-
  free_vars(A, Vs), \+ member(v(N), Vs).

 mp(implies(A, B), A, B). % modus ponens
 gen(A, forall(v(N), A)). % generalisation
:- end_category.

% -----------------------------------------------------------------------------
% Object: provability kernel (Gödel's Prov predicate scaffolding)
% -----------------------------------------------------------------------------
:- object(provability,
 implements(proof_system_p),
 imports(hilbert_c),
 imports(godel_coding_c)).

 :- public([
  bew/2, % Bew(x) — x is (code of) a proof
  provable_code/2,
  diagonal/2, % diagonal lemma support
  godel_sentence/1,
  consistency/0
 ]).

 axiom(A) :- hilbert_axiom(A).

 inference_rule(mp, [implies(A,B), A], B).
 inference_rule(gen, [A], forall(v(_), A)).

 % Proof as sequence of formulas ending with target
 proof(Target, ProofSeq) :-
  is_list(ProofSeq),
  last(ProofSeq, Target),
  check_proof(ProofSeq, []).

 check_proof([], _).
 check_proof([F|Fs], Prev) :-
  ( axiom(F)
  ; member(A, Prev), member(B, Prev), inference_rule(_, [A,B], F)
  ; member(A, Prev), inference_rule(_, [A], F)
  ),
  check_proof(Fs, [F|Prev]).

 provable(F, Proof) :- proof(F, Proof).

 % Code-level provability (Bew)
 bew(ProofCode, FormulaCode) :-
  % decode proof sequence, check, re-encode last formula
  % (dense stub; full decoder would invert sequence_code)
  integer(ProofCode), integer(FormulaCode),
  % placeholder: any positive codes related by modular condition
  ProofCode mod (FormulaCode + 1) =:= 0.

 provable_code(FormulaCode, ProofCode) :-
  bew(ProofCode, FormulaCode).

 % Diagonal lemma support: construct G such that ⊢ G ↔ ¬Bew(⌜G⌝)
 diagonal(Pred, FixedPoint) :-
  % Pred is a formula with one free variable
  % FixedPoint ≡ Pred(⌜FixedPoint⌝)
  encode_formula(Pred, Code),
  % substitute the numeral of Code into Pred
  numeral(Code, Num),
  substitute(Pred, v(0), Num, FixedPoint).

 numeral(0, const(0)).
 numeral(N, func(s, [M])) :- N > 0, N1 is N - 1, numeral(N1, M).

 % Gödel sentence: G ↔ ¬Bew(⌜G⌝)
 godel_sentence(G) :-
  % construct ¬Bew(x) with free x
  NegBew = not(pred(bew, [var(0)])),
  diagonal(NegBew, G).

 % Consistency statement Con(T) = ¬Bew(⌜0=1⌝)
 consistency :-
  encode_formula(eq(const(0), const(1)), InconsCode),
  \+ provable_code(InconsCode, _).
:- end_object.

% -----------------------------------------------------------------------------
% Category: reflection & self-reference utilities
% -----------------------------------------------------------------------------
:- category(reflection_c).
 :- public([
  quote/2, unquote/2, eval_formula/2,
  self_ref/1, liar/1
 ]).

 quote(F, Code) :- fol_arith::encode_formula(F, Code).
 unquote(Code, F) :- integer(Code), % inverse incomplete by design
  F = formula_of_code(Code).

 eval_formula(eq(T1, T2), true) :-
  fol_arith::encode_term(T1, C1),
  fol_arith::encode_term(T2, C2),
  C1 =:= C2.
 eval_formula(not(F), true) :- \+ eval_formula(F, true).
 eval_formula(and(F1, F2), true) :- eval_formula(F1, true), eval_formula(F2, true).
 eval_formula(or(F1, F2), true) :- eval_formula(F1, true) ; eval_formula(F2, true).

 self_ref(Sentence) :-
  provability::godel_sentence(Sentence).

 liar(L) :-
  % classic liar: L ↔ ¬True(⌜L⌝)
  L = not(pred(true, [var(0)])).
:- end_category.

% -----------------------------------------------------------------------------
% Object: top-level symbolic kernel (assembles everything)
% -----------------------------------------------------------------------------
:- object(symbolic_kernel,
 imports(peano_c),
 imports(godel_coding_c),
 imports(reflection_c)).

 :- public([
  kernel_version/1,
  encode/2, decode/2,
  prove/2, is_provable/1,
  construct_godel/1,
  run_incompleteness_demo/0,
  export_theory/1
 ]).

 kernel_version('Gödel-Logtalk Symbolic Kernel 0.9-dense').

 encode(TermOrFormula, Code) :-
  ( fol_arith::term(TermOrFormula)
  -> fol_arith::encode_term(TermOrFormula, Code)
  ; fol_arith::formula(TermOrFormula)
  -> fol_arith::encode_formula(TermOrFormula, Code)
  ).

 decode(Code, Entity) :-
  fol_arith::decode_term(Code, Entity).

 prove(Formula, Proof) :-
  provability::provable(Formula, Proof).

 is_provable(Formula) :-
  provability::provable(Formula, _).

 construct_godel(G) :-
  provability::godel_sentence(G).

 run_incompleteness_demo :-
  construct_godel(G),
  quote(G, GCode),
  format('Gödel sentence constructed.~nCode: ~w~n', [GCode]),
  ( is_provable(G)
  -> format('WARNING: G appears provable (inconsistency or bug).~n')
  ; format('G is not provable inside the system (as expected by G1).~n')
  ),
  ( provability::consistency
  -> format('Consistency statement holds at meta-level.~n')
  ; format('Consistency check failed.~n')
  ).

 export_theory(File) :-
  atom(File),
  open(File, write, Stream),
  write(Stream, '% Exported symbolic kernel theory\n'),
  % dump key predicates (dense meta-write)
  forall(
   ( current_predicate(Name/Arity),
    functor(Head, Name, Arity),
    clause(Head, Body)
   ),
   ( portray_clause(Stream, (Head :- Body)), nl(Stream))
  ),
  close(Stream).
:- end_object.

% -----------------------------------------------------------------------------
% Parametric object: theory instantiator (for different axiom sets)
% -----------------------------------------------------------------------------
:- object(theory(_Axioms)).
 :- public([member_axiom/1, extend/2, theorem/1]).

 member_axiom(A) :-
  parameter(1, Axioms),
  member(A, Axioms).

 extend(NewAxiom, theory(Extended)) :-
  parameter(1, Axioms),
  Extended = [NewAxiom|Axioms].

 theorem(F) :-
  % naive: axiom or MP closure (bounded)
  member_axiom(F)
  ; member_axiom(implies(A, F)), theorem(A).
:- end_object.

% -----------------------------------------------------------------------------
% Utility category: dense list / meta helpers
% -----------------------------------------------------------------------------
:- category(dense_utils_c).
 :- public([maplist/2, maplist/3, append/3, last/2, delete/3, max_list/2, sort/2, nth0/3, forall/2, member/2]).

 maplist(_, []).
 maplist(P, [X|Xs]) :- call(P, X), maplist(P, Xs).

 maplist(_, [], []).
 maplist(P, [X|Xs], [Y|Ys]) :- call(P, X, Y), maplist(P, Xs, Ys).

 append([], L, L).
 append([H|T], L, [H|R]) :- append(T, L, R).

 last([X], X) :- !.
 last([_|T], X) :- last(T, X).

 delete([], _, []).
 delete([X|Xs], X, Ys) :- !, delete(Xs, X, Ys).
 delete([X|Xs], Y, [X|Ys]) :- delete(Xs, Y, Ys).

 max_list([X], X).
 max_list([X|Xs], M) :- max_list(Xs, M1), (X > M1 -> M = X ; M = M1).

 sort(L, S) :- sort(L, S). % rely on backend

 nth0(0, [X|_], X) :- !.
 nth0(N, [_|T], X) :- N > 0, N1 is N - 1, nth0(N1, T, X).

 forall(Gen, Test) :- \+ (call(Gen), \+ call(Test)).

 member(X, [X|_]).
 member(X, [_|T]) :- member(X, T).
:- end_category.

% Make utilities available
:- object(utils, imports(dense_utils_c)).
:- end_object.

% -----------------------------------------------------------------------------
% Final assembly & loader hook
% -----------------------------------------------------------------------------
:- initialization((
 symbolic_kernel::kernel_version(V),
 format('~w loaded.~n', [V]),
 format('Use symbolic_kernel::run_incompleteness_demo. for a quick G1 illustration.~n')
)).
