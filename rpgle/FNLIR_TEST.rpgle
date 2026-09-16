**free
ctl-opt dftactgrp(*no) actgrp(*caller) option(*srcstmt : *nodebugio);

/*
 FNLIR_TEST - Unit test harness for FunnelParseAndBuildIR
 - Calls FunnelParseAndBuildIR(src, srcLen, outJson, outLen, status)
 - Runs multiple Funnel examples and asserts IR JSON contains expected tokens
 - Simple substring-based assertions for portability
*/

/* Prototype for the parser service program (from FNLIRTR) */
dcl-pr FunnelParseAndBuildIR extpgm('FunnelParseAndBuildIR');
  pSrc char(*) const;
  pSrcLen packed(9:0) const;
  pOutJson char(32768);
  pOutLen packed(9:0);
  pStatus char(16);
end-pr;

/* Small display helper */
dcl-proc show;
  dcl-pi *n;
    msg char(1024) const;
  end-pi;
  dsply msg;
end-proc;

/* Assertion helper: checks substring presence */
dcl-proc assertContains;
  dcl-pi *n ind;
    pJson char(32768) const;
    pJsonLen packed(9:0) const;
    pNeed char(256) const;
    pTestName char(128) const;
  end-pi;

  dcl-s found ind inz(*off);
  dcl-s j int(10);

  if %len(%trim(pNeed)) = 0;
    found = *off;
  else;
    j = %scan(%trim(pNeed) : %subst(pJson : 1 : pJsonLen));
    if j > 0;
      found = *on;
    else;
      found = *off;
    endif;
  endif;

  if found;
    dsply ('PASS: ' + %trim(pTestName) + ' -> contains "' + %trim(pNeed) + '"');
    return *on;
  else;
    dsply ('FAIL: ' + %trim(pTestName) + ' -> missing "' + %trim(pNeed) + '"');
    return *off;
  endif;
end-proc;

/* Test vector structure */
dcl-ds TestCase qualified;
  name char(64);
  src  char(8192);
  expectCount packed(5:0);
  expects char(20) dim(20) char(128); /* up to 20 expected substrings */
end-ds;

/* Populate test cases */
dcl-s tests dim(10) likeds(TestCase);
dcl-s testCount packed(5:0) inz(0);

/* Helper to add a test case */
dcl-proc addTest;
  dcl-pi *n;
    pName char(64) const;
    pSrc char(8192) const;
    pExpects char(20) dim(20) char(128) const;
    pExpectCount packed(5:0) const;
  end-pi;

  testCount += 1;
  tests(testCount).name = pName;
  tests(testCount).src  = pSrc;
  tests(testCount).expectCount = pExpectCount;
  dcl-s i int(5) inz(1);
  dow i <= pExpectCount;
    tests(testCount).expects(i) = pExpects(i);
    i += 1;
  enddo;
end-proc;

/* Define test vectors (three examples) */
dcl-s ex1Src char(8192) inz(
'PROGRAM ach_return.' +
'TYPE State = NEW | POSTED | SETTLED | RETURNED.' +
'RECORD Item { company : CHAR(3). batch : CHAR(10). entry : CHAR(15). state : State. amount : NUM(13,2). reason : CHAR(3). }.' +
'FILE achitem USING ACHITEM KEY company(3), batch(10), entry(15).' +
'RULE returnable(item : Item) = item.state IN (State.POSTED, State.SETTLED).' +
'PROC return_item(item : Item, reason : CHAR(3)) = REQUIRE returnable(item). REQUIRE item.state != State.RETURNED. item.state := State.RETURNED. item.reason := reason. SAVE item. .'
);

dcl-s ex2Src char(8192) inz(
'PROGRAM ledger_post.' +
'RECORD Ledger { company : CHAR(3). date : CHAR(8). seq : NUM(9,0). amount : NUM(15,2). drcr : CHAR(1). }.' +
'FILE ledger USING LEDGER KEY company(3), date(8), seq(9).' +
'PROC post_entry(company : CHAR(3), date : CHAR(8), seq : NUM(9,0), amount : NUM(15,2), drcr : CHAR(1)) = ' +
'LOAD Ledger(company, date, seq) AS it. IF it.state = "" THEN SAVE it. ENDIF. .'
);

dcl-s ex3Src char(8192) inz(
'PROGRAM simple_types.' +
'TYPE Color = RED | GREEN | BLUE.' +
'RECORD Palette { id : NUM(9,0). name : CHAR(20). color : Color. }.' +
'FILE palette USING PALETTE KEY id(9).' +
'PROC set_color(p : Palette, c : Color) = p.color := c. SAVE p. .'
);

/* expected substrings for assertions */
dcl-s ex1Exp char(20) dim(20) char(128) inz;
ex1Exp(1) = '"types"';
ex1Exp(2) = '"State"';
ex1Exp(3) = '"records"';
ex1Exp(4) = '"Item"';
ex1Exp(5) = '"files"';
ex1Exp(6) = '"achitem"';
ex1Exp(7) = '"rules"';
ex1Exp(8) = '"returnable"';
ex1Exp(9) = '"procs"';
ex1Exp(10)= '"return_item"';

dcl-s ex2Exp char(20) dim(20) char(128) inz;
ex2Exp(1) = '"records"';
ex2Exp(2) = '"Ledger"';
ex2Exp(3) = '"files"';
ex2Exp(4) = '"ledger"';
ex2Exp(5) = '"procs"';
ex2Exp(6) = '"post_entry"';

dcl-s ex3Exp char(20) dim(20) char(128) inz;
ex3Exp(1) = '"types"';
ex3Exp(2) = '"Color"';
ex3Exp(3) = '"records"';
ex3Exp(4) = '"Palette"';
ex3Exp(5) = '"files"';
ex3Exp(6) = '"palette"';
ex3Exp(7) = '"procs"';
ex3Exp(8) = '"set_color"';

/* Add tests */
callp addTest('ach_return' : ex1Src : ex1Exp : 10);
callp addTest('ledger_post' : ex2Src : ex2Exp : 6);
callp addTest('simple_types' : ex3Src : ex3Exp : 8);

/* Test runner */
dcl-s total int(10) inz(0);
dcl-s passed int(10) inz(0);
dcl-s failed int(10) inz(0);

dcl-s outJson char(32768);
dcl-s outLen packed(9:0);
dcl-s status char(16);

/* iterate tests */
dcl-s ti int(5) inz(1);
dow ti <= testCount;
  total += 1;
  dsply ('--- Running test: ' + %trim(tests(ti).name) + ' ---');
  /* call parser */
  outJson = *blanks;
  outLen = 0;
  status = *blanks;
  callp FunnelParseAndBuildIR(tests(ti).src : %len(%trim(tests(ti).src)) : outJson : outLen : status);

  if status <> 'OK';
    dsply ('ERROR: parser returned status=' + %trim(status));
    failed += 1;
    ti += 1;
    iterate;
  endif;

  /* Basic sanity: outLen > 0 */
  if outLen = 0;
    dsply ('FAIL: no IR produced');
    failed += 1;
    ti += 1;
    iterate;
  endif;

  /* Run expectations */
  dcl-s allOk ind inz(*on);
  dcl-s ei int(5) inz(1);
  dow ei <= tests(ti).expectCount;
    dcl-s need char(128) inz(tests(ti).expects(ei));
    if %len(%trim(need)) = 0;
      ei += 1;
      iterate;
    endif;
    if not assertContains(outJson : outLen : need : tests(ti).name + ' [' + %char(ei) + ']');
      allOk = *off;
    endif;
    ei += 1;
  enddo;

  if allOk;
    passed += 1;
    dsply ('RESULT: ' + %trim(tests(ti).name) + ' => PASS');
  else;
    failed += 1;
    dsply ('RESULT: ' + %trim(tests(ti).name) + ' => FAIL');
    /* Optionally dump IR for debugging */
    dsply ('IR JSON:');
    dsply (%subst(outJson : 1 : outLen));
  endif;

  ti += 1;
enddo;

/* Summary */
dsply ('====================');
dsply ('Total tests: ' + %char(total));
dsply ('Passed:      ' + %char(passed));
dsply ('Failed:      ' + %char(failed));
dsply ('====================');

/* Return nonzero on failure for CI */
if failed > 0;
  *inlr = *on;
  return;
endif;

*inlr = *on;
return;
