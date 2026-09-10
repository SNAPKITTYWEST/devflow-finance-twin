# Funnel Language Grammar v0.1

```
program      ::= "PROGRAM" ident "." decl* ;

decl         ::= typeDecl
               | recordDecl
               | fileDecl
               | ruleDecl
               | procDecl ;

typeDecl     ::= "TYPE" ident "=" enumType "." ;
enumType     ::= enumAlt ("|" enumAlt)* ;
enumAlt      ::= ident ;

recordDecl   ::= "RECORD" ident "{" fieldDecl* "}" "." ;
fieldDecl    ::= ident ":" typeRef "." ;

typeRef      ::= "CHAR" "(" number ")"
               | "NUM" "(" number [ "," number ] ")"
               | ident ;  (* user-defined types, e.g. State *)

fileDecl     ::= "FILE" ident "USING" ident
                 "KEY" keyField ("," keyField)* "." ;
keyField     ::= ident "(" number ")" ;

ruleDecl     ::= "RULE" ident "(" paramList? ")" "=" expr "." ;

procDecl     ::= "PROC" ident "(" paramList? ")" "=" procBody "." ;

paramList    ::= param ("," param)* ;
param        ::= ident ":" typeRef ;

procBody     ::= stmt+ ;

stmt         ::= "REQUIRE" expr "."
               | "LOAD" ident "(" exprList? ")" "AS" ident "."
               | "SAVE" ident "."
               | ident ":=" expr "."
               | "IF" expr "THEN" stmt+ ["ELSE" stmt+] "ENDIF."
               | "FAIL" stringLiteral "."
               ;

exprList     ::= expr ("," expr)* ;

expr         ::= orExpr ;
orExpr       ::= andExpr ( "OR" andExpr )* ;
andExpr      ::= notExpr ( "AND" notExpr )* ;
notExpr      ::= [ "NOT" ] relExpr ;
relExpr      ::= sumExpr ( relOp sumExpr )? ;
relOp        ::= "=" | "!=" | "<" | "<=" | ">" | ">=" | "IN" ;
sumExpr      ::= primary ;  (* v0.1: no arithmetic chains yet *)

primary      ::= ident
               | ident "." ident        (* record.field *)
               | stringLiteral
               | number
               | "(" expr ")"
               | enumLiteral ;

enumLiteral  ::= ident "." ident ;  (* Type.Variant *)
```
