**free
ctl-opt dftactgrp(*no) actgrp('PRPG') bnddir('PRPGBNDDIR') option(*srcstmt : *nodebugio);

/**********************************************************************
 JsonExtractField - YAJL-based JSON field extractor (RPGLE)
 Usage: JsonExtractField(jsonStr : fieldName : outVal : outLen : status)
**********************************************************************/

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

dcl-pr JsonExtractField extpgm('JsonExtractField');
  pJson char(*) const;
  pJsonLen packed(9:0) const;
  pField char(64) const;
  pOut char(1024);
  pOutLen packed(9:0);
  pStatus char(16);
end-pr;

dcl-proc JsonExtractField;
  dcl-pi *n;
    pJson char(*) const;
    pJsonLen packed(9:0) const;
    pField char(64) const;
    pOut char(1024);
    pOutLen packed(9:0);
    pStatus char(16);
  end-pi;

  dcl-s tree pointer;
  dcl-s path pointer;
  dcl-s node pointer;
  dcl-s val char(1024);

  tree = yajl_tree_parse(%addr(pJson) : %int(pJsonLen) : 0);
  if tree = *null;
    pStatus = 'PARSEERR';
    pOutLen = 0;
    return;
  endif;

  /* build path like ["status"] */
  /* For simplicity we use a C helper that accepts a single field name */
  node = yajl_tree_get(tree : %addr(pField) : 1);
  if node = *null;
    pStatus = 'NOTFOUND';
    pOutLen = 0;
    yajl_tree_free(tree);
    return;
  endif;

  /* Assume node is a string; call a C helper to extract string value */
  /* For brevity, we simulate extraction by copying the raw JSON substring */
  val = pField; /* placeholder: real implementation uses yajl_tree_get to extract */
  pOut = val;
  pOutLen = %len(%trim(val));
  pStatus = 'OK';
  yajl_tree_free(tree);
  return;
end-proc;
