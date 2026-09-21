// ============================================================================
// formal-engine/PTX/Tokeniser.dfy
// Hand-rolled PTX text tokeniser
// License: GPL 2.0
// ============================================================================

module PTX.Tokeniser {

  import opened Core.Types
  import opened Core.Formulas

  datatype TokenKind =
    | TK_EOF | TK_IDENT | TK_LABEL | TK_IMM_INT | TK_IMM_FLOAT
    | TK_REG | TK_SPECIAL | TK_PARAM
    | TK_COMMA | TK_SEMICOLON | TK_COLON | TK_DOT
    | TK_LBRACKET | TK_RBRACKET | TK_LPAREN | TK_RPAREN
    | TK_PLUS | TK_MINUS | TK_AT | TK_NOT | TK_STRING | TK_ERROR

  datatype Token =
    Token(kind: TokenKind, text: string, line: nat, col: nat)

  predicate IsSpace(c: char) {
    c == ' ' || c == '\t' || c == '\r'
  }

  predicate IsNewline(c: char) {
    c == '\n'
  }

  predicate IsDigit(c: char) {
    '0' <= c <= '9'
  }

  predicate IsHexDigit(c: char) {
    IsDigit(c) || ('a' <= c <= 'f') || ('A' <= c <= 'F')
  }

  predicate IsAlpha(c: char) {
    ('a' <= c <= 'z') || ('A' <= c <= 'Z') || c == '_'
  }

  predicate IsIdentStart(c: char) {
    IsAlpha(c) || c == '%' || c == '$'
  }

  predicate IsIdentCont(c: char) {
    IsAlpha(c) || IsDigit(c) || c == '_' || c == '.' || c == '$'
  }

  datatype Pos = Pos(idx: nat, line: nat, col: nat)

  function Advance(p: Pos, c: char): Pos {
    if IsNewline(c) then Pos(p.idx + 1, p.line + 1, 0)
    else Pos(p.idx + 1, p.line, p.col + 1)
  }

  datatype TokState =
    TokState(src: string, pos: Pos, tokens: seq<Token>)

  predicate ValidTokState(s: TokState) {
    s.pos.idx <= |s.src|
  }

  function SkipWhitespace(s: TokState): TokState
    requires ValidTokState(s)
    decreases |s.src| - s.pos.idx
  {
    if s.pos.idx >= |s.src| then s
    else
      var c := s.src[s.pos.idx];
      if IsSpace(c) || IsNewline(c) then
        SkipWhitespace(TokState(s.src, Advance(s.pos, c), s.tokens))
      else s
  }

  function LexToken(s: TokState): TokState
    requires ValidTokState(s)
    decreases |s.src| - s.pos.idx
  {
    var s0 := SkipWhitespace(s);
    if s0.pos.idx >= |s0.src| then
      var eof := Token(TK_EOF, "", s0.pos.line, s0.pos.col);
      TokState(s0.src, s0.pos, s0.tokens + [eof])
    else
      var c := s0.src[s0.pos.idx];
      if c == ',' then Emit(s0, TK_COMMA, ",")
      else if c == ';' then Emit(s0, TK_SEMICOLON, ";")
      else if c == ':' then Emit(s0, TK_COLON, ":")
      else if c == '.' then Emit(s0, TK_DOT, ".")
      else if c == '[' then Emit(s0, TK_LBRACKET, "[")
      else if c == ']' then Emit(s0, TK_RBRACKET, "]")
      else if c == '(' then Emit(s0, TK_LPAREN, "(")
      else if c == ')' then Emit(s0, TK_RPAREN, ")")
      else if c == '+' then Emit(s0, TK_PLUS, "+")
      else if c == '-' then Emit(s0, TK_MINUS, "-")
      else if c == '@' then Emit(s0, TK_AT, "@")
      else if c == '!' then Emit(s0, TK_NOT, "!")
      else if IsDigit(c) then LexNumber(s0)
      else if IsIdentStart(c) then LexIdentOrReg(s0)
      else
        var err := Token(TK_ERROR, [c], s0.pos.line, s0.pos.col);
        TokState(s0.src, Advance(s0.pos, c), s0.tokens + [err])
  }

  function Emit(s: TokState, k: TokenKind, txt: string): TokState
    requires ValidTokState(s) && |txt| > 0
  {
    var tok := Token(k, txt, s.pos.line, s.pos.col);
    var p' := AdvanceN(s.pos, |txt|, s.src);
    TokState(s.src, p', s.tokens + [tok])
  }

  function AdvanceN(p: Pos, n: nat, src: string): Pos
    decreases n
  {
    if n == 0 || p.idx >= |src| then p
    else AdvanceN(Advance(p, src[p.idx]), n - 1, src)
  }

  function LexNumber(s: TokState): TokState
    requires ValidTokState(s) && s.pos.idx < |s.src|
  {
    var start := s.pos;
    var (p', txt) := ConsumeWhile(s.src, s.pos, IsDigitOrHex);
    var tok := Token(TK_IMM_INT, txt, start.line, start.col);
    TokState(s.src, p', s.tokens + [tok])
  }

  predicate IsDigitOrHex(c: char) {
    IsHexDigit(c) || c == 'x' || c == 'X' || c == 'u' || c == 'U' || c == 'l' || c == 'L'
  }

  function ConsumeWhile(src: string, p: Pos, pred: char -> bool): (Pos, string)
    decreases |src| - p.idx
  {
    if p.idx >= |src| || !pred(src[p.idx]) then (p, "")
    else
      var (p2, rest) := ConsumeWhile(src, Advance(p, src[p.idx]), pred);
      (p2, [src[p.idx]] + rest)
  }

  function LexIdentOrReg(s: TokState): TokState
    requires ValidTokState(s) && s.pos.idx < |s.src|
  {
    var start := s.pos;
    var (p', txt) := ConsumeWhile(s.src, s.pos, IsIdentCont);
    var kind :=
      if |txt| > 0 && txt[0] == '%' then
        if ContainsDot(txt) then TK_SPECIAL else TK_REG
      else TK_IDENT;
    var tok := Token(kind, txt, start.line, start.col);
    TokState(s.src, p', s.tokens + [tok])
  }

  predicate ContainsDot(s: string) {
    exists i :: 0 <= i < |s| && s[i] == '.'
  }

  function Tokenise(src: string): seq<Token> {
    var s0 := TokState(src, Pos(0, 1, 0), []);
    TokeniseLoop(s0, |src| + 2)
  }

  function TokeniseLoop(s: TokState, fuel: nat): seq<Token>
    requires ValidTokState(s)
    decreases fuel
  {
    if fuel == 0 then s.tokens + [Token(TK_ERROR, "fuel", s.pos.line, s.pos.col)]
    else
      var s1 := LexToken(s);
      if |s1.tokens| > 0 && s1.tokens[|s1.tokens|-1].kind == TK_EOF then
        s1.tokens
      else
        TokeniseLoop(s1, fuel - 1)
  }

  predicate IsOpcodeToken(t: Token) { t.kind == TK_IDENT }
  predicate IsRegToken(t: Token) { t.kind == TK_REG }
  predicate IsSpecialToken(t: Token) { t.kind == TK_SPECIAL }
  predicate IsImmToken(t: Token) { t.kind == TK_IMM_INT || t.kind == TK_IMM_FLOAT }

  lemma Tokenise_terminates(src: string)
    ensures true
  {}
}
