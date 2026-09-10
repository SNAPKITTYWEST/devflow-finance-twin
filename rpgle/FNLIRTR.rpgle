**free
ctl-opt dftactgrp(*no) actgrp('FNLIRTR') bnddir('PRPGBNDDIR') option(*srcstmt : *nodebugio);

/**********************************************************************
 FNLIRTR - Funnel parser + AST -> Business IR translator (RPGLE)
 - Exposes: FunnelParseAndBuildIR(src, srcLen, outJson, outLen, status)
 - Uses YAJL (C library) for JSON emission (binding shown below)
 - Produces authoritative Business IR JSON consumed by backends
**********************************************************************/

/* External YAJL bindings (C library must be available and bound) */
dcl-pr yajl_gen_alloc pointer extproc('yajl_gen_alloc');
  pcfg pointer value options(*nopass);
end-pr;

dcl-pr yajl_gen_free extproc('yajl_gen_free');
  gen pointer value;
end-pr;

dcl-pr yajl_gen_config int(10) extproc('yajl_gen_config');
  gen pointer value;
  cfg int(10) value;
  val int(10) value;
end-pr;

dcl-pr yajl_gen_string int(10) extproc('yajl_gen_string');
  gen pointer value;
  str pointer value;
  len int(10) value;
end-pr;

dcl-pr yajl_gen_map_open int(10) extproc('yajl_gen_map_open');
  gen pointer value;
end-pr;

dcl-pr yajl_gen_map_close int(10) extproc('yajl_gen_map_close');
  gen pointer value;
end-pr;

dcl-pr yajl_gen_array_open int(10) extproc('yajl_gen_array_open');
  gen pointer value;
end-pr;

dcl-pr yajl_gen_array_close int(10) extproc('yajl_gen_array_close');
  gen pointer value;
end-pr;

dcl-pr yajl_gen_integer int(10) extproc('yajl_gen_integer');
  gen pointer value;
  val int(10) value;
end-pr;

dcl-pr yajl_gen_double int(10) extproc('yajl_gen_double');
  gen pointer value;
  val double value;
end-pr;

dcl-pr yajl_gen_bool int(10) extproc('yajl_gen_bool');
  gen pointer value;
  val int(10) value;
end-pr;

dcl-pr yajl_gen_get_buf pointer extproc('yajl_gen_get_buf');
  gen pointer value;
  len pointer value;
end-pr;

/* Simple constants */
dcl-const MAXSRC int(32768);
dcl-const MAXOUT int(32768);

/* Public prototype */
dcl-pr FunnelParseAndBuildIR extpgm('FunnelParseAndBuildIR');
  pSrc char(*) const;
  pSrcLen packed(9:0) const;
  pOutJson char(32768);
  pOutLen packed(9:0);
  pStatus char(16);
end-pr;

/* Internal data structures (compact) */

/* Token */
dcl-ds Token qualified;
  typ char(16);
  val char(256);
  pos packed(9:0);
end-ds;

/* AST node kinds */
dcl-ds AstProgram qualified;
  name char(64);
  declCount packed(9:0);
  decls pointer dim(200);
end-ds;

/* We'll represent AST decls as simple tagged records in memory using pointers
   Each decl is a small JSON-like structure stored in RPG data areas.
   For brevity we use a compact in-memory representation and then emit IR JSON.
*/

/* Symbol tables for semantic analysis */
dcl-ds SymType qualified dim(200);
  tname char(64);
  tkind char(16); /* ENUM | CHAR | NUM | RECORDREF */
  variants char(1024);
  charLen packed(9:0);
  numP packed(9:0);
  numS packed(9:0);
end-ds;

dcl-s symTypeCount packed(9:0) inz(0);

dcl-ds SymRecord qualified dim(200);
  rname char(64);
  fieldCount packed(9:0);
  fieldNames char(2000);
  fieldTypes char(2000);
end-ds;
dcl-s symRecordCount packed(9:0) inz(0);

dcl-ds SymFile qualified dim(200);
  fname char(64);
  storage char(64);
  keyFields char(256);
end-ds;
dcl-s symFileCount packed(9:0) inz(0);

/* Minimal tokenizer for Funnel v0.1 */
dcl-proc tokenize;
  dcl-pi *n int(10);
    pSrc char(*) const;
    pSrcLen packed(9:0) const;
    pTokens pointer;
    pCount pointer;
  end-pi;

  dcl-s i int(10) inz(1);
  dcl-s pos int(10) inz(1);
  dcl-s len int(10);
  dcl-s ch char(1);
  dcl-s buf char(32768);
  dcl-s tokCount int(10) inz(0);

  len = %len(%subst(pSrc:1:pSrcLen));
  buf = %subst(pSrc:1:pSrcLen);

  dow pos <= len;
    ch = %subst(buf:pos:1);
    /* skip whitespace */
    if ch = ' ' or ch = x'0A' or ch = x'0D' or ch = x'09';
      pos += 1;
      iterate;
    endif;
    /* comments // to EOL */
    if pos < len and %subst(buf:pos:2) = '//';
      /* skip to newline */
      dcl-s j int(10) inz(pos+2);
      dow j <= len and %subst(buf:j:1) <> x'0A';
        j += 1;
      enddo;
      pos = j + 1;
      iterate;
    endif;
    /* identifiers/keywords */
    if (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or ch = '_';
      dcl-s start int(10) inz(pos);
      dcl-s j int(10) inz(pos);
      dow j <= len;
        dcl-s c char(1) inz(%subst(buf:j:1));
        if (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '_' or c = '.';
          j += 1;
        else;
          leave;
        endif;
      enddo;
      dcl-s tok char(256);
      tok = %subst(buf:start:(j-start));
      /* uppercase keywords */
      if %scan('PROGRAM TYPE RECORD FILE USING KEY RULE PROC REQUIRE SAVE LOAD AS IF THEN ELSE ENDIF IN FAIL ENUM CHAR NUM STATE', %upper(tok)) > 0;
        /* token is keyword */
        /* store token */
        tokCount += 1;
        %addr(tok) = %addr(tok); /* no-op to avoid optimization */
        /* allocate token area */
        /* For brevity, we store tokens in a simple flat string array via pointer arithmetic */
        /* In production, use dynamic storage or arrays of structures */
      else;
        tokCount += 1;
      endif;
      pos = j;
      iterate;
    endif;
    /* numbers */
    if ch >= '0' and ch <= '9';
      dcl-s start int(10) inz(pos);
      dcl-s j int(10) inz(pos);
      dow j <= len and (%subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9' or %subst(buf:j:1) = '.');
        j += 1;
      enddo;
      pos = j;
      tokCount += 1;
      iterate;
    endif;
    /* strings */
    if ch = '"';
      dcl-s j int(10) inz(pos+1);
      dow j <= len and %subst(buf:j:1) <> '"';
        if %subst(buf:j:1) = '\'';
          j += 2;
        else;
          j += 1;
        endif;
      enddo;
      pos = j + 1;
      tokCount += 1;
      iterate;
    endif;
    /* punctuation single char tokens */
    pos += 1;
    tokCount += 1;
  enddo;

  /* For this compact prototype we return token count only; the parser below
     reads directly from the source using simple pattern matching functions.
     This keeps the code dense and avoids complex token storage. */
  return tokCount;
end-proc;

/* Helper: skip whitespace and comments (used by parser) */
dcl-proc skipws;
  dcl-pi *n;
    pSrc char(*) const;
    pLen packed(9:0) const;
    pPos packed(9:0);
  end-pi;
  dcl-s pos int(10) inz(pPos);
  dcl-s len int(10) inz(pLen);
  dcl-s buf char(32768);
  buf = %subst(pSrc:1:pLen);
  dow pos <= len;
    dcl-s ch char(1) inz(%subst(buf:pos:1));
    if ch = ' ' or ch = x'0A' or ch = x'0D' or ch = x'09';
      pos += 1;
      iterate;
    endif;
    if pos < len and %subst(buf:pos:2) = '//';
      dcl-s j int(10) inz(pos+2);
      dow j <= len and %subst(buf:j:1) <> x'0A';
        j += 1;
      enddo;
      pos = j + 1;
      iterate;
    endif;
    leave;
  enddo;
  return pos;
end-proc;

/* Very small parser functions that extract named constructs by pattern matching.
   This is intentionally compact: we parse TYPE, RECORD, FILE, RULE, PROC blocks.
   The parser returns success/failure and populates symbol tables. */

dcl-proc parse_program;
  dcl-pi *n ind;
    pSrc char(*) const;
    pSrcLen packed(9:0) const;
    pErr char(256);
  end-pi;

  dcl-s pos packed(9:0) inz(1);
  dcl-s len packed(9:0) inz(pSrcLen);
  dcl-s buf char(32768);
  buf = %subst(pSrc:1:pSrcLen);

  /* expect PROGRAM <ident> . */
  pos = skipws(pSrc : pSrcLen : pos);
  if %subst(buf:pos:7) <> 'PROGRAM';
    pErr = 'Missing PROGRAM';
    return *off;
  endif;
  pos += 7;
  pos = skipws(pSrc : pSrcLen : pos);
  /* read program name */
  dcl-s name char(64);
  dcl-s i int(10) inz(pos);
  dow i <= len and (%subst(buf:i:1) >= 'A' and %subst(buf:i:1) <= 'Z' or %subst(buf:i:1) >= 'a' and %subst(buf:i:1) <= 'z' or %subst(buf:i:1) = '_' or %subst(buf:i:1) >= '0' and %subst(buf:i:1) <= '9');
    i += 1;
  enddo;
  name = %trim(%subst(buf:pos:(i-pos)));
  pos = i;
  pos = skipws(pSrc : pSrcLen : pos);
  if %subst(buf:pos:1) <> '.';
    pErr = 'Expected . after PROGRAM name';
    return *off;
  endif;
  pos += 1;

  /* loop over declarations */
  dow pos <= len;
    pos = skipws(pSrc : pSrcLen : pos);
    if pos > len; leave; endif;
    /* check for TYPE */
    if %subst(buf:pos:4) = 'TYPE';
      pos += 4; pos = skipws(pSrc : pSrcLen : pos);
      /* read typename */
      dcl-s tname char(64);
      dcl-s j int(10) inz(pos);
      dow j <= len and (%subst(buf:j:1) >= 'A' and %subst(buf:j:1) <= 'Z' or %subst(buf:j:1) >= 'a' and %subst(buf:j:1) <= 'z' or %subst(buf:j:1) = '_' or %subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9');
        j += 1;
      enddo;
      tname = %trim(%subst(buf:pos:(j-pos)));
      pos = j; pos = skipws(pSrc : pSrcLen : pos);
      /* expect = */
      if %subst(buf:pos:1) <> '=';
        pErr = 'Expected = in TYPE';
        return *off;
      endif;
      pos += 1; pos = skipws(pSrc : pSrcLen : pos);
      /* parse variants separated by | until '.' */
      dcl-s variants char(1024) inz('');
      dow pos <= len and %subst(buf:pos:1) <> '.';
        /* read variant */
        dcl-s k int(10) inz(pos);
        dow k <= len and (%subst(buf:k:1) <> '|' and %subst(buf:k:1) <> '.');
          k += 1;
        enddo;
        variants += %trim(%subst(buf:pos:(k-pos))) + '|';
        pos = k;
        if %subst(buf:pos:1) = '|'; pos += 1; endif;
        pos = skipws(pSrc : pSrcLen : pos);
      enddo;
      /* store type */
      symTypeCount += 1;
      symType(symTypeCount).tname = %trim(tname);
      symType(symTypeCount).tkind = 'ENUM';
      symType(symTypeCount).variants = %trim(variants);
      pos += 1; /* skip '.' */
      iterate;
    endif;

    /* RECORD */
    if %subst(buf:pos:6) = 'RECORD';
      pos += 6; pos = skipws(pSrc : pSrcLen : pos);
      dcl-s rname char(64);
      dcl-s j int(10) inz(pos);
      dow j <= len and (%subst(buf:j:1) >= 'A' and %subst(buf:j:1) <= 'Z' or %subst(buf:j:1) >= 'a' and %subst(buf:j:1) <= 'z' or %subst(buf:j:1) = '_' or %subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9');
        j += 1;
      enddo;
      rname = %trim(%subst(buf:pos:(j-pos)));
      pos = j; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:1) <> '{';
        pErr = 'Expected { after RECORD name';
        return *off;
      endif;
      pos += 1;
      /* parse fields until } */
      dcl-s fieldNames char(2000) inz('');
      dcl-s fieldTypes char(2000) inz('');
      dow pos <= len and %subst(buf:pos:1) <> '}';
        pos = skipws(pSrc : pSrcLen : pos);
        /* field name */
        dcl-s fname char(64);
        dcl-s k int(10) inz(pos);
        dow k <= len and (%subst(buf:k:1) >= 'A' and %subst(buf:k:1) <= 'Z' or %subst(buf:k:1) >= 'a' and %subst(buf:k:1) <= 'z' or %subst(buf:k:1) = '_' or %subst(buf:k:1) >= '0' and %subst(buf:k:1) <= '9');
          k += 1;
        enddo;
        fname = %trim(%subst(buf:pos:(k-pos)));
        pos = k; pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) <> ':';
          pErr = 'Expected : in field declaration';
          return *off;
        endif;
        pos += 1; pos = skipws(pSrc : pSrcLen : pos);
        /* type: CHAR(n) | NUM(p,s) | user type */
        dcl-s tkn char(64);
        if %subst(buf:pos:4) = 'CHAR';
          pos += 4; pos = skipws(pSrc : pSrcLen : pos);
          if %subst(buf:pos:1) <> '('; pErr='Expected ('; return *off; endif;
          pos += 1;
          dcl-s numstr char(16);
          dcl-s m int(10) inz(pos);
          dow m <= len and %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9';
            m += 1;
          enddo;
          numstr = %trim(%subst(buf:pos:(m-pos)));
          pos = m;
          if %subst(buf:pos:1) <> ')'; pErr='Expected )'; return *off; endif;
          pos += 1;
          tkn = 'CHAR(' + numstr + ')';
        elseif %subst(buf:pos:3) = 'NUM';
          pos += 3; pos = skipws(pSrc : pSrcLen : pos);
          if %subst(buf:pos:1) <> '('; pErr='Expected ('; return *off; endif;
          pos += 1;
          dcl-s pstr char(8); dcl-s sstr char(8);
          dcl-s m int(10) inz(pos);
          dow m <= len and %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9';
            m += 1;
          enddo;
          pstr = %trim(%subst(buf:pos:(m-pos)));
          pos = m;
          if %subst(buf:pos:1) = ','; pos += 1; end-if;
          m = pos;
          dow m <= len and %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9';
            m += 1;
          enddo;
          sstr = %trim(%subst(buf:pos:(m-pos)));
          pos = m;
          if %subst(buf:pos:1) <> ')'; pErr='Expected )'; return *off; endif;
          pos += 1;
          tkn = 'NUM(' + pstr + ',' + sstr + ')';
        else;
          /* user type */
          dcl-s m int(10) inz(pos);
          dow m <= len and (%subst(buf:m:1) >= 'A' and %subst(buf:m:1) <= 'Z' or %subst(buf:m:1) >= 'a' and %subst(buf:m:1) <= 'z' or %subst(buf:m:1) = '_' or %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9');
            m += 1;
          enddo;
          tkn = %trim(%subst(buf:pos:(m-pos)));
          pos = m;
        endif;
        pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) <> '.';
          pErr = 'Expected . after field';
          return *off;
        endif;
        pos += 1;
        /* append to record */
        fieldNames += fname + '|';
        fieldTypes += tkn + '|';
      enddo;
      /* store record */
      symRecordCount += 1;
      symRecord(symRecordCount).rname = %trim(rname);
      symRecord(symRecordCount).fieldCount = %int(%scan('|' : fieldNames)) - 1;
      symRecord(symRecordCount).fieldNames = fieldNames;
      symRecord(symRecordCount).fieldTypes = fieldTypes;
      pos += 1; /* skip '}' */
      pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:1) <> '.';
        pErr = 'Expected . after RECORD block';
        return *off;
      endif;
      pos += 1;
      iterate;
    endif;

    /* FILE */
    if %subst(buf:pos:4) = 'FILE';
      pos += 4; pos = skipws(pSrc : pSrcLen : pos);
      dcl-s fname char(64);
      dcl-s j int(10) inz(pos);
      dow j <= len and (%subst(buf:j:1) >= 'A' and %subst(buf:j:1) <= 'Z' or %subst(buf:j:1) >= 'a' and %subst(buf:j:1) <= 'z' or %subst(buf:j:1) = '_' or %subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9');
        j += 1;
      enddo;
      fname = %trim(%subst(buf:pos:(j-pos)));
      pos = j; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:5) <> 'USING';
        pErr = 'Expected USING in FILE';
        return *off;
      endif;
      pos += 5; pos = skipws(pSrc : pSrcLen : pos);
      dcl-s storage char(64);
      j = pos;
      dow j <= len and (%subst(buf:j:1) >= 'A' and %subst(buf:j:1) <= 'Z' or %subst(buf:j:1) >= 'a' and %subst(buf:j:1) <= 'z' or %subst(buf:j:1) = '_' or %subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9');
        j += 1;
      enddo;
      storage = %trim(%subst(buf:pos:(j-pos)));
      pos = j; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:3) <> 'KEY';
        pErr = 'Expected KEY in FILE';
        return *off;
      endif;
      pos += 3; pos = skipws(pSrc : pSrcLen : pos);
      /* parse key fields like name(n), name2(n) separated by commas */
      dcl-s keyfields char(256) inz('');
      dow pos <= len and %subst(buf:pos:1) <> '.';
        /* read field name */
        dcl-s kname char(64);
        dcl-s m int(10) inz(pos);
        dow m <= len and (%subst(buf:m:1) >= 'A' and %subst(buf:m:1) <= 'Z' or %subst(buf:m:1) >= 'a' and %subst(buf:m:1) <= 'z' or %subst(buf:m:1) = '_' or %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9');
          m += 1;
        enddo;
        kname = %trim(%subst(buf:pos:(m-pos)));
        pos = m; pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) = '(';
          /* skip size */
          pos += 1;
          dcl-s npos int(10) inz(pos);
          dow npos <= len and %subst(buf:npos:1) <> ')';
            npos += 1;
          enddo;
          pos = npos + 1;
        endif;
        keyfields += kname + '|';
        pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) = ','; pos += 1; end-if;
      enddo;
      /* store file */
      symFileCount += 1;
      symFile(symFileCount).fname = %trim(fname);
      symFile(symFileCount).storage = %trim(storage);
      symFile(symFileCount).keyFields = keyfields;
      pos += 1; /* skip '.' */
      iterate;
    endif;

    /* RULE */
    if %subst(buf:pos:4) = 'RULE';
      pos += 4; pos = skipws(pSrc : pSrcLen : pos);
      /* read name */
      dcl-s rname char(64);
      dcl-s j int(10) inz(pos);
      dow j <= len and (%subst(buf:j:1) >= 'A' and %subst(buf:j:1) <= 'Z' or %subst(buf:j:1) >= 'a' and %subst(buf:j:1) <= 'z' or %subst(buf:j:1) = '_' or %subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9');
        j += 1;
      enddo;
      rname = %trim(%subst(buf:pos:(j-pos)));
      pos = j; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:1) <> '('; pErr='Expected ('; return *off; endif;
      pos += 1;
      /* parse params until ) */
      dcl-s params char(256) inz('');
      dow pos <= len and %subst(buf:pos:1) <> ')';
        /* param name : type */
        dcl-s pname char(64);
        dcl-s k int(10) inz(pos);
        dow k <= len and (%subst(buf:k:1) >= 'A' and %subst(buf:k:1) <= 'Z' or %subst(buf:k:1) >= 'a' and %subst(buf:k:1) <= 'z' or %subst(buf:k:1) = '_' or %subst(buf:k:1) >= '0' and %subst(buf:k:1) <= '9');
          k += 1;
        enddo;
        pname = %trim(%subst(buf:pos:(k-pos)));
        pos = k; pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) <> ':'; pErr='Expected :' ; return *off; endif;
        pos += 1; pos = skipws(pSrc : pSrcLen : pos);
        /* type name */
        dcl-s tname char(64);
        dcl-s m int(10) inz(pos);
        dow m <= len and (%subst(buf:m:1) >= 'A' and %subst(buf:m:1) <= 'Z' or %subst(buf:m:1) >= 'a' and %subst(buf:m:1) <= 'z' or %subst(buf:m:1) = '_' or %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9');
          m += 1;
        enddo;
        tname = %trim(%subst(buf:pos:(m-pos)));
        pos = m;
        params += pname + ':' + tname + '|';
        pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) = ','; pos += 1; end-if;
      enddo;
      pos += 1; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:1) <> '='; pErr='Expected =' ; return *off; endif;
      pos += 1; pos = skipws(pSrc : pSrcLen : pos);
      /* read expression until '.' */
      dcl-s expr char(1024) inz('');
      dcl-s kpos int(10) inz(pos);
      dow kpos <= len and %subst(buf:kpos:1) <> '.';
        expr += %subst(buf:kpos:1);
        kpos += 1;
      enddo;
      pos = kpos + 1;
      /* store rule as simple text (we'll translate later) */
      symTypeCount += 0; /* no-op */
      /* For compactness, we store rules in a simple file-like area: use symFile array as scratch */
      symFile(symFileCount+1).fname = rname;
      symFile(symFileCount+1).storage = expr;
      symFileCount += 1;
      iterate;
    endif;

    /* PROC */
    if %subst(buf:pos:4) = 'PROC';
      pos += 4; pos = skipws(pSrc : pSrcLen : pos);
      dcl-s pname char(64);
      dcl-s j int(10) inz(pos);
      dow j <= len and (%subst(buf:j:1) >= 'A' and %subst(buf:j:1) <= 'Z' or %subst(buf:j:1) >= 'a' and %subst(buf:j:1) <= 'z' or %subst(buf:j:1) = '_' or %subst(buf:j:1) >= '0' and %subst(buf:j:1) <= '9');
        j += 1;
      enddo;
      pname = %trim(%subst(buf:pos:(j-pos)));
      pos = j; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:1) <> '('; pErr='Expected ('; return *off; endif;
      pos += 1;
      /* params */
      dcl-s params char(512) inz('');
      dow pos <= len and %subst(buf:pos:1) <> ')';
        /* param name : type */
        dcl-s pname2 char(64);
        dcl-s k int(10) inz(pos);
        dow k <= len and (%subst(buf:k:1) >= 'A' and %subst(buf:k:1) <= 'Z' or %subst(buf:k:1) >= 'a' and %subst(buf:k:1) <= 'z' or %subst(buf:k:1) = '_' or %subst(buf:k:1) >= '0' and %subst(buf:k:1) <= '9');
          k += 1;
        enddo;
        pname2 = %trim(%subst(buf:pos:(k-pos)));
        pos = k; pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) <> ':'; pErr='Expected :' ; return *off; endif;
        pos += 1; pos = skipws(pSrc : pSrcLen : pos);
        dcl-s tname2 char(64);
        dcl-s m int(10) inz(pos);
        dow m <= len and (%subst(buf:m:1) >= 'A' and %subst(buf:m:1) <= 'Z' or %subst(buf:m:1) >= 'a' and %subst(buf:m:1) <= 'z' or %subst(buf:m:1) = '_' or %subst(buf:m:1) >= '0' and %subst(buf:m:1) <= '9');
          m += 1;
        enddo;
        tname2 = %trim(%subst(buf:pos:(m-pos)));
        pos = m;
        params += pname2 + ':' + tname2 + '|';
        pos = skipws(pSrc : pSrcLen : pos);
        if %subst(buf:pos:1) = ','; pos += 1; end-if;
      enddo;
      pos += 1; pos = skipws(pSrc : pSrcLen : pos);
      if %subst(buf:pos:1) <> '='; pErr='Expected =' ; return *off; endif;
      pos += 1; pos = skipws(pSrc : pSrcLen : pos);
      /* read body until '.' (single dot terminator) */
      dcl-s body char(4096) inz('');
      dcl-s kpos int(10) inz(pos);
      dow kpos <= len and %subst(buf:kpos:1) <> '.';
        body += %subst(buf:kpos:1);
        kpos += 1;
      enddo;
      pos = kpos + 1;
      /* store proc as simple record in symFile array */
      symFile(symFileCount+1).fname = pname;
      symFile(symFileCount+1).storage = params;
      symFile(symFileCount+1).keyFields = body;
      symFileCount += 1;
      iterate;
    endif;

    /* if nothing matched, break to avoid infinite loop */
    leave;
  enddo;

  return *on;
end-proc;

/* Build IR JSON using YAJL */
dcl-proc build_ir_json;
  dcl-pi *n ind;
    pOut char(32768);
    pOutLen packed(9:0);
    pStatus char(16);
  end-pi;

  dcl-s gen pointer;
  dcl-s buf pointer;
  dcl-s buflen int(10);

  gen = yajl_gen_alloc(*null);
  if gen = *null;
    pStatus = 'YAJLERR';
    return *off;
  endif;

  yajl_gen_map_open(gen);

  /* types */
  yajl_gen_string(gen : %addr('types') : %len('types'));
  yajl_gen_array_open(gen);
  dcl-s i int(10) inz(1);
  dow i <= symTypeCount;
    yajl_gen_map_open(gen);
    yajl_gen_string(gen : %addr('name') : %len('name'));
    yajl_gen_string(gen : %addr(symType(i).tname) : %len(%trim(symType(i).tname)));
    yajl_gen_string(gen : %addr('kind') : %len('kind'));
    yajl_gen_string(gen : %addr(symType(i).tkind) : %len(%trim(symType(i).tkind)));
    if symType(i).tkind = 'ENUM';
      yajl_gen_string(gen : %addr('variants') : %len('variants'));
      yajl_gen_string(gen : %addr(symType(i).variants) : %len(%trim(symType(i).variants)));
    endif;
    yajl_gen_map_close(gen);
    i += 1;
  enddo;
  yajl_gen_array_close(gen);

  /* records */
  yajl_gen_string(gen : %addr('records') : %len('records'));
  yajl_gen_array_open(gen);
  i = 1;
  dow i <= symRecordCount;
    yajl_gen_map_open(gen);
    yajl_gen_string(gen : %addr('name') : %len('name'));
    yajl_gen_string(gen : %addr(symRecord(i).rname) : %len(%trim(symRecord(i).rname)));
    yajl_gen_string(gen : %addr('fields') : %len('fields'));
    yajl_gen_array_open(gen);
    /* split fieldNames and fieldTypes by '|' */
    dcl-s fnames char(2000) inz(symRecord(i).fieldNames);
    dcl-s ftypes char(2000) inz(symRecord(i).fieldTypes);
    dcl-s idx int(10) inz(1);
    dow idx <= %len(fnames);
      dcl-s p int(10) inz(%scan('|' : fnames : idx));
      if p = 0; leave; endif;
      dcl-s fname char(64) inz(%trim(%subst(fnames:idx:(p-idx))));
      dcl-s q int(10) inz(%scan('|' : ftypes : idx));
      dcl-s ftype char(64) inz(%trim(%subst(ftypes:idx:(q-idx))));
      yajl_gen_map_open(gen);
      yajl_gen_string(gen : %addr('name') : %len('name'));
      yajl_gen_string(gen : %addr(fname) : %len(%trim(fname)));
      yajl_gen_string(gen : %addr('type') : %len('type'));
      yajl_gen_string(gen : %addr(ftype) : %len(%trim(ftype)));
      yajl_gen_map_close(gen);
      idx = p + 1;
    enddo;
    yajl_gen_array_close(gen);
    yajl_gen_map_close(gen);
    i += 1;
  enddo;
  yajl_gen_array_close(gen);

  /* files */
  yajl_gen_string(gen : %addr('files') : %len('files'));
  yajl_gen_array_open(gen);
  i = 1;
  dow i <= symFileCount;
    yajl_gen_map_open(gen);
    yajl_gen_string(gen : %addr('name') : %len('name'));
    yajl_gen_string(gen : %addr(symFile(i).fname) : %len(%trim(symFile(i).fname)));
    yajl_gen_string(gen : %addr('storage') : %len('storage'));
    yajl_gen_string(gen : %addr(symFile(i).storage) : %len(%trim(symFile(i).storage)));
    yajl_gen_string(gen : %addr('keys') : %len('keys'));
    yajl_gen_string(gen : %addr(symFile(i).keyFields) : %len(%trim(symFile(i).keyFields)));
    yajl_gen_map_close(gen);
    i += 1;
  enddo;
  yajl_gen_array_close(gen);

  yajl_gen_map_close(gen);

  buf = yajl_gen_get_buf(gen : %addr(buflen));
  if buf = *null;
    pStatus = 'YAJLBUF';
    yajl_gen_free(gen);
    return *off;
  endif;

  /* copy buffer to pOut */
  if buflen > %size(pOut);
    pStatus = 'TOOLONG';
    yajl_gen_free(gen);
    return *off;
  endif;

  pOut = %str(buf : buflen);
  pOutLen = buflen;
  pStatus = 'OK';
  yajl_gen_free(gen);
  return *on;
end-proc;

/* Public entry: FunnelParseAndBuildIR */
dcl-proc FunnelParseAndBuildIR;
  dcl-pi *n;
    pSrc char(*) const;
    pSrcLen packed(9:0) const;
    pOutJson char(32768);
    pOutLen packed(9:0);
    pStatus char(16);
  end-pi;

  dcl-s err char(256);

  /* parse */
  if not parse_program(pSrc : pSrcLen : err);
    pStatus = 'PARSEERR';
    pOutLen = 0;
    return;
  endif;

  /* build IR JSON */
  if not build_ir_json(pOutJson : pOutLen : pStatus);
    /* pStatus set by build_ir_json */
    pOutLen = 0;
    return;
  endif;

  return;
end-proc;

/* End of FNLIRTR */
*inlr = *on;
return;