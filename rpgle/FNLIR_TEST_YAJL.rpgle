**free
ctl-opt dftactgrp(*no) actgrp(*caller) option(*srcstmt : *nodebugio);

/*
  FNLIR_TEST_YAJL - YAJL-backed unit test harness for Funnel parser -> IR
  - Structural assertions via yajl_tree_get
  - Positive and negative tests
  - Writes CI result JSON to /tmp/fnlir_test_results.json
  - Writes CI status file /tmp/fnlir_test_ci_status (0 = pass, 1 = fail)
  - Dumps full IR JSON to job log on failure for debugging
*/

/* Prototype: Funnel parser service (from FNLIRTR) */
dcl-pr FunnelParseAndBuildIR extpgm('FunnelParseAndBuildIR');
  pSrc char(*) const;
  pSrcLen packed(9:0) const;
  pOutJson char(32768);
  pOutLen packed(9:0);
  pStatus char(16);
end-pr;

/* YAJL tree bindings (yajl_tree) */
dcl-pr yajl_tree_parse pointer extproc('yajl_tree_parse');
  json pointer value;
  jsonlen int(10) value;
  flags int(10) value;
end-pr;

dcl-pr yajl_tree_get pointer extproc('yajl_tree_get');
  tree pointer value;
  path pointer value;
  pathlen int(10) value;
end-pr;

dcl-pr yajl_tree_free extproc('yajl_tree_free');
  tree pointer value;
end-pr;

/* Helper to extract string value from a yajl node (C helper expected) */
dcl-pr yajl_node_get_string pointer extproc('yajl_node_get_string');
  node pointer value;
end-pr;

/* IFS file write helper */
dcl-pr writeFile extpgm('WRITE_FILE');
  pPath char(1024) const;
  pData char(*) const;
  pLen packed(9:0) const;
  pStatus char(16);
end-pr;

/* Small display helper */
dcl-proc log;
  dcl-pi *n;
    msg char(1024) const;
  end-pi;
  dsply msg;
end-proc;

/* Test case structure */
dcl-ds TestCase qualified;
  name char(64);
  src  char(16384);
  expectCount packed(5:0);
  expects char(20) dim(40) char(256); /* up to 40 assertions */
  negativeFlag ind;
  expectedError char(32);
end-ds;

/* Test result structure for CI JSON */
dcl-ds TestResult qualified;
  name char(64);
  passed ind;
  details char(32768);
end-ds;

/* Test arrays */
dcl-s tests dim(20) likeds(TestCase);
dcl-s results dim(20) likeds(TestResult);
dcl-s testCount packed(5:0) inz(0);
dcl-s resultCount packed(5:0) inz(0);

/* Add test helper */
dcl-proc addTest;
  dcl-pi *n;
    pName char(64) const;
    pSrc char(16384) const;
    pExpects char(20) dim(40) char(256) const;
    pExpectCount packed(5:0) const;
    pNegative ind;
    pExpectedError char(32) const;
  end-pi;

  testCount += 1;
  tests(testCount).name = pName;
  tests(testCount).src  = pSrc;
  tests(testCount).expectCount = pExpectCount;
  tests(testCount).negativeFlag = pNegative;
  tests(testCount).expectedError = pExpectedError;
  dcl-s i int(5) inz(1);
  dow i <= pExpectCount;
    tests(testCount).expects(i) = pExpects(i);
    i += 1;
  enddo;
end-proc;

/* Assertion via YAJL tree: path is array of path elements (char*), pathLen is number of elements.
   We support:
     - path elements that are names (e.g., "records")
     - numeric indices as strings (e.g., "0")
   The function returns the string value of the node or blank if not found.
*/
dcl-proc yajlGetString;
  dcl-pi *n char(1024);
    pJson char(*) const;
    pJsonLen packed(9:0) const;
    pPath char(256) const; /* dot-separated path, e.g., records.0.fields.2.type */
  end-pi;

  dcl-s tree pointer;
  dcl-s node pointer;
  dcl-s status char(16);
  dcl-s parts char(256) inz(pPath);
  dcl-s pathElems pointer;
  dcl-s pathCount int(10) inz(0);
  dcl-s i int(10) inz(1);
  dcl-s seg char(64);
  dcl-s pos int(10) inz(1);
  dcl-s len int(10) inz(%len(%subst(pJson:1:pJsonLen)));
  dcl-s tmp char(1024) inz(*blanks);

  /* parse JSON into tree */
  tree = yajl_tree_parse(%addr(pJson) : %int(pJsonLen) : 0);
  if tree = *null;
    return *blanks;
  endif;

  /* split pPath by '.' into C-style array on the stack (we will call yajl_tree_get with pointer to array) */
  /* For compactness we build a C-style path string with null separators and pass its address and count */
  dcl-s cpath char(1024) inz(*blanks);
  dcl-s cpos int(10) inz(1);
  pos = 1;
  dow pos <= %len(%trim(parts));
    dcl-s dotpos int(10) inz(%scan('.' : parts : pos));
    if dotpos = 0;
      seg = %trim(%subst(parts:pos));
      pos = %len(%trim(parts)) + 1;
    else;
      seg = %trim(%subst(parts:pos:(dotpos-pos)));
      pos = dotpos + 1;
    endif;
    /* append seg and a null char */
    cpath = %subst(cpath : 1 : cpos - 1) + seg + x'00';
    cpos += %len(%trim(seg)) + 1;
    pathCount += 1;
  enddo;

  /* call yajl_tree_get: it expects an array of char* pointers; many yajl_tree_get wrappers accept a C array of char*.
     For portability we call yajl_tree_get with the C-style path buffer and pathCount; the binding above assumes
     the C wrapper will accept (tree, pathBuffer, pathCount). If your yajl_tree_get requires a char** array,
     implement a small C shim that accepts a single buffer with null-separated strings.
  */
  node = yajl_tree_get(tree : %addr(cpath) : pathCount);
  if node = *null;
    yajl_tree_free(tree);
    return *blanks;
  endif;

  /* extract string value from node using helper; if null, return blank */
  dcl-s sval pointer;
  sval = yajl_node_get_string(node);
  if sval = *null;
    yajl_tree_free(tree);
    return *blanks;
  endif;

  /* copy C string into RPG char */
  tmp = %str(sval : %len(%trim(%str(sval))));
  yajl_tree_free(tree);
  return tmp;
end-proc;

/* Assertion helper using yajlGetString */
dcl-proc assertYajlEquals;
  dcl-pi *n ind;
    pJson char(32768) const;
    pJsonLen packed(9:0) const;
    pPath char(256) const;   /* dot-separated path */
    pExpected char(256) const;
    pTestName char(128) const;
  end-pi;

  dcl-s val char(1024);
  val = yajlGetString(pJson : pJsonLen : pPath);
  if %len(%trim(val)) = 0;
    dsply ('FAIL: ' + %trim(pTestName) + ' -> path ' + %trim(pPath) + ' not found');
    return *off;
  endif;
  if %trim(val) = %trim(pExpected);
    dsply ('PASS: ' + %trim(pTestName) + ' -> ' + %trim(pPath) + ' == "' + %trim(pExpected) + '"');
    return *on;
  else;
    dsply ('FAIL: ' + %trim(pTestName) + ' -> ' + %trim(pPath) + ' != "' + %trim(pExpected) + '" (got "' + %trim(val) + '")');
    return *off;
  endif;
end-proc;

/* Add positive test: return_item */
dcl-s ex1Exp char(20) dim(20) char(256) inz;
ex1Exp(1) = 'records.0.name'; ex1Exp(2) = 'Item';
ex1Exp(3) = 'records.0.fields.4.type'; ex1Exp(4) = 'NUM(13,2)';
ex1Exp(5) = 'files.0.name'; ex1Exp(6) = 'achitem';
ex1Exp(7) = 'types.0.name'; ex1Exp(8) = 'State';

dcl-s ex1Src char(8192) inz(
'PROGRAM ach_return.' +
'TYPE State = NEW | POSTED | SETTLED | RETURNED.' +
'RECORD Item { company : CHAR(3). batch : CHAR(10). entry : CHAR(15). state : State. amount : NUM(13,2). reason : CHAR(3). }.' +
'FILE achitem USING ACHITEM KEY company(3), batch(10), entry(15).' +
'RULE returnable(item : Item) = item.state IN (State.POSTED, State.SETTLED).' +
'PROC return_item(item : Item, reason : CHAR(3)) = REQUIRE returnable(item). REQUIRE item.state != State.RETURNED. item.state := State.RETURNED. item.reason := reason. SAVE item. .'
);

callp addTest('ach_return' : ex1Src : ex1Exp : 4 : *off : *blanks);

/* Add negative test: malformed TYPE (missing '=') */
dcl-s neg1Src char(4096) inz(
'PROGRAM bad1.' +
'TYPE BadType NEW | A | B.' + /* malformed: missing '=' */
'RECORD R { id : NUM(9,0). }.' +
'FILE r USING R KEY id(9).' +
'PROC p(r : R) = SAVE r. .'
);
dcl-s neg1Exp char(20) dim(20) char(256) inz;
neg1Exp(1) = 'PARSEERR';
callp addTest('bad_type_missing_eq' : neg1Src : neg1Exp : 1 : *on : 'PARSEERR');

/* Add negative test: illegal field type */
dcl-s neg2Src char(4096) inz(
'PROGRAM bad2.' +
'RECORD R { id : UNKNOWNTYPE. }.' +
'FILE r USING R KEY id(9).' +
'PROC p(r : R) = SAVE r. .'
);
dcl-s neg2Exp char(20) dim(20) char(256) inz;
neg2Exp(1) = 'SEMERR';
callp addTest('bad_field_type' : neg2Src : neg2Exp : 1 : *on : 'SEMERR');

/* Add more tests as needed... */

/* Runner */
dcl-s i int(5) inz(1);
dcl-s outJson char(32768);
dcl-s outLen packed(9:0);
dcl-s status char(16);
dcl-s passed int(10) inz(0);
dcl-s failed int(10) inz(0);

dcl-s testResJson char(32768) inz(*blanks);
dcl-s perTestJson char(4096);

dcl-s ciResults char(32768) inz(*blanks);

/* Build results array */
ciResults = '{ "tests": [';

dow i <= testCount;
  outJson = *blanks; outLen = 0; status = *blanks;
  callp FunnelParseAndBuildIR(tests(i).src : %len(%trim(tests(i).src)) : outJson : outLen : status);

  dcl-s thisPassed ind inz(*off);
  thisPassed = *off;
  perTestJson = '{ "name": "' + %trim(tests(i).name) + '", "status": "' + %trim(status) + '", "assertions": [';

  if tests(i).negativeFlag;
    /* Expect an error code in status */
    if %trim(status) = %trim(tests(i).expectedError);
      thisPassed = *on;
      passed += 1;
      perTestJson += '{"expect":"error","result":"matched"}';
    else;
      failed += 1;
      perTestJson += '{"expect":"error","result":"mismatch","expected":"' + %trim(tests(i).expectedError) + '","got":"' + %trim(status) + '"}';
      /* Dump IR JSON for debugging if any produced */
      if outLen > 0;
        dsply('DEBUG IR for ' + %trim(tests(i).name) + ':');
        dsply(%subst(outJson : 1 : outLen));
      endif;
    endif;
  else;
    /* Positive test: parse must succeed */
    if %trim(status) <> 'OK';
      failed += 1;
      perTestJson += '{"expect":"ok","result":"parse_failed","status":"' + %trim(status) + '"}';
      /* dump any IR */
      if outLen > 0;
        dsply('DEBUG IR for ' + %trim(tests(i).name) + ':');
        dsply(%subst(outJson : 1 : outLen));
      endif;
      i += 1;
      ciResults += perTestJson + ']},';
      iterate;
    endif;

    /* For each structural expectation, use yajlGetString */
    dcl-s j int(5) inz(1);
    dcl-s allOk ind inz(*on);
    dow j <= tests(i).expectCount;
      dcl-s path char(256) inz(tests(i).expects(j));
      dcl-s expected char(256) inz(tests(i).expects(j+1));
      if %len(%trim(path)) = 0;
        leave;
      endif;
      /* call yajlGetString */
      dcl-s got char(1024) inz(*blanks);
      got = yajlGetString(outJson : outLen : path);
      if %len(%trim(got)) = 0;
        allOk = *off;
        perTestJson += '{"path":"' + %trim(path) + '","expected":"' + %trim(expected) + '","result":"missing"},';
        dsply('FAIL: ' + %trim(tests(i).name) + ' -> missing path ' + %trim(path));
      else;
        if %trim(got) = %trim(expected);
          perTestJson += '{"path":"' + %trim(path) + '","expected":"' + %trim(expected) + '","result":"ok"},';
          dsply('PASS: ' + %trim(tests(i).name) + ' -> ' + %trim(path) + ' == "' + %trim(expected) + '"');
        else;
          allOk = *off;
          perTestJson += '{"path":"' + %trim(path) + '","expected":"' + %trim(expected) + '","got":"' + %trim(got) + '","result":"mismatch"},';
          dsply('FAIL: ' + %trim(tests(i).name) + ' -> ' + %trim(path) + ' != "' + %trim(expected) + '" (got "' + %trim(got) + '")');
        endif;
      endif;
      j += 2; /* path + expected are stored in pairs */
    enddo;

    if allOk;
      passed += 1;
      thisPassed = *on;
      perTestJson += '"summary":"PASS"';
    else;
      failed += 1;
      thisPassed = *off;
      perTestJson += '"summary":"FAIL"';
      /* dump full IR JSON for debugging */
      if outLen > 0;
        dsply('DEBUG IR for ' + %trim(tests(i).name) + ':');
        dsply(%subst(outJson : 1 : outLen));
      endif;
    endif;
  endif;

  perTestJson += '] }';
  /* append to ciResults */
  if i < testCount;
    ciResults += perTestJson + ',';
  else;
    ciResults += perTestJson;
  endif;

  i += 1;
enddo;

ciResults += '], "summary": { "total": ' + %char(testCount) + ', "passed": ' + %char(passed) + ', "failed": ' + %char(failed) + ' } }';

/* Write CI result file */
dcl-s statusOut char(16);
callp writeFile('/tmp/fnlir_test_results.json' : ciResults : %len(%trim(ciResults)) : statusOut);
if statusOut <> 'OK';
  dsply('WARN: failed to write CI results file: ' + %trim(statusOut));
endif;

/* Write CI status file (0 = all pass, 1 = any fail) */
dcl-s ciStatus char(4);
if failed > 0;
  ciStatus = '1';
else;
  ciStatus = '0';
endif;
callp writeFile('/tmp/fnlir_test_ci_status' : ciStatus : %len(ciStatus) : statusOut);

/* Final summary to job log */
dsply('FNLIR TEST SUMMARY: total=' + %char(testCount) + ' passed=' + %char(passed) + ' failed=' + %char(failed));
if failed > 0;
  dsply('One or more tests failed. See /tmp/fnlir_test_results.json and job log for details.');
else;
  dsply('All tests passed.');
endif;

/* Return: CI runner should inspect /tmp/fnlir_test_ci_status (1 = fail) */
*inlr = *on;
return;

/* ---------------------------------------------------------------------------
   Minimal IFS write helper implementation (synchronous)
   This uses Qshell 'cat > file' via QCMDEXC for portability in compact examples.
   In production, use open/write/close APIs or Qp2 services.
   --------------------------------------------------------------------------- */
dcl-pr QCMDEXC extpgm('QCMDEXC');
  cmd char(32767) const;
  len packed(15:5) const;
end-pr;

dcl-proc WRITE_FILE;
  dcl-pi *n;
    pPath char(1024) const;
    pData char(*) const;
    pLen packed(9:0) const;
    pStatus char(16);
  end-pi;

  dcl-s cmd char(32767);
  dcl-s escData char(32768);
  dcl-s qlen packed(15:5);

  /* Use printf-style here: echo 'data' > /tmp/file */
  /* Escape single quotes in data */
  escData = %trim(pData);
  escData = %xlate('''' : ''''"'"''': escData); /* replace ' with '\'' */
  cmd = 'QSH CMD(''' || 'printf "%s" "' || escData || '" > ' || pPath || ''')';
  qlen = %len(%trim(cmd));
  QCMDEXC(cmd : qlen);
  pStatus = 'OK';
end-proc;
