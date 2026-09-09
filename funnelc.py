#!/usr/bin/env python3
# funnelc.py -- compact single-file prototype implementing:
#  - minimal Funnel parser (v0.1)
#  - AST
#  - semantic analyzer / type system
#  - Business IR (authoritative)
#  - backends: COBOL, Prolog, Mercury (small subset)
#  - example: return_item / ach_return
#
# Usage:
#   python3 funnelc.py input.fnl --target cobol|prolog|mercury
#
# Notes:
#  - intentionally dense, minimal error handling
#  - implements core constructs from the spec: TYPE, RECORD, FILE, RULE, PROC, REQUIRE, LOAD, SAVE, IF, ASSIGN, FAIL
#  - IR is authoritative; backends implement IR
#  - Designed as a starting point for v0.1

import sys, re, textwrap, json
from typing import List, Tuple, Dict, Any, Optional, Union

# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------
KEYWORDS = {
    "PROGRAM","TYPE","RECORD","FILE","USING","KEY","RULE","PROC","REQUIRE",
    "SAVE","LOAD","AS","IF","THEN","ELSE","ENDIF","IN","FAIL","ENUM","NUM",
    "CHAR","STATE","ENDPROC","ENDRULE"
}
TOKEN_SPEC = [
    ('NUMBER',   r'\d+(\.\d+)?'),
    ('ID',       r'[A-Za-z_][A-Za-z0-9_]*'),
    ('STRING',   r'"([^"\\]|\\.)*"'),
    ('EQ',       r':='),
    ('OP',       r'<=|>=|!=|=|<|>'),
    ('LP',       r'\('),
    ('RP',       r'\)'),
    ('LBR',      r'\{'),
    ('RBR',      r'\}'),
    ('COMMA',    r','),
    ('COL',      r':'),
    ('DOT',      r'\.'),
    ('WS',       r'[ \t\r\n]+'),
    ('COMMENT',  r'//.*'),
]
TOK_REGEX = re.compile('|'.join('(?P<%s>%s)' % pair for pair in TOKEN_SPEC))
class Token:
    def __init__(self, typ, val, pos):
        self.typ = typ
        self.val = val
        self.pos = pos
    def __repr__(self):
        return f"Token({self.typ},{self.val})"

def lex(src: str):
    pos = 0
    tokens = []
    for m in TOK_REGEX.finditer(src):
        typ = m.lastgroup
        val = m.group(0)
        if typ == 'WS' or typ == 'COMMENT':
            continue
        if typ == 'ID' and val.upper() in KEYWORDS:
            typ = val.upper()
            val = val.upper()
        tokens.append(Token(typ, val, m.start()))
    tokens.append(Token('EOF','',len(src)))
    return tokens

# ---------------------------------------------------------------------------
# AST nodes (compact)
# ---------------------------------------------------------------------------
class ASTNode: pass
class Program(ASTNode):
    def __init__(self,name,decls): self.name=name; self.decls=decls
class TypeDecl(ASTNode):
    def __init__(self,name,variants): self.name=name; self.variants=variants
class RecordDecl(ASTNode):
    def __init__(self,name,fields): self.name=name; self.fields=fields
class FileDecl(ASTNode):
    def __init__(self,name,storage,keyfields): self.name=name; self.storage=storage; self.keyfields=keyfields
class RuleDecl(ASTNode):
    def __init__(self,name,params,expr): self.name=name; self.params=params; self.expr=expr
class ProcDecl(ASTNode):
    def __init__(self,name,params,body): self.name=name; self.params=params; self.body=body
class Param(ASTNode):
    def __init__(self,name,typ): self.name=name; self.typ=typ
class Field(ASTNode):
    def __init__(self,name,typ): self.name=name; self.typ=typ

# Statements and expressions
class Stmt(ASTNode): pass
class Require(Stmt):
    def __init__(self,expr): self.expr=expr
class Load(Stmt):
    def __init__(self,recname,keys,alias): self.recname=recname; self.keys=keys; self.alias=alias
class Save(Stmt):
    def __init__(self,alias): self.alias=alias
class Assign(Stmt):
    def __init__(self,target,expr): self.target=target; self.expr=expr
class IfStmt(Stmt):
    def __init__(self,cond,thenStmts,elseStmts): self.cond=cond; self.thenStmts=thenStmts; self.elseStmts=elseStmts
class Fail(Stmt):
    def __init__(self,msg): self.msg=msg

class Expr(ASTNode): pass
class Ident(Expr):
    def __init__(self,name): self.name=name
class FieldRef(Expr):
    def __init__(self,alias,field): self.alias=alias; self.field=field
class Literal(Expr):
    def __init__(self,val): self.val=val
class EnumLit(Expr):
    def __init__(self,typename,variant): self.typename=typename; self.variant=variant
class BinOp(Expr):
    def __init__(self,op,l,r): self.op=op; self.l=l; self.r=r
class InExpr(Expr):
    def __init__(self,left,vals): self.left=left; self.vals=vals

# ---------------------------------------------------------------------------
# Parser (recursive descent, minimal)
# ---------------------------------------------------------------------------
class Parser:
    def __init__(self,toks):
        self.toks=toks; self.i=0
    def cur(self): return self.toks[self.i]
    def eat(self,typ=None):
        t=self.cur()
        if typ and t.typ!=typ:
            self.error(f"Expected {typ} got {t.typ} at {t.pos}")
        self.i+=1
        return t
    def error(self,msg): raise SyntaxError(msg)
    def parse(self):
        # PROGRAM name . decl*
        if self.cur().typ!='PROGRAM': self.error("Program must start with PROGRAM")
        self.eat('PROGRAM'); name=self.eat('ID').val; self.eat('DOT')
        decls=[]
        while self.cur().typ!='EOF':
            if self.cur().typ=='TYPE':
                decls.append(self.parse_type())
            elif self.cur().typ=='RECORD':
                decls.append(self.parse_record())
            elif self.cur().typ=='FILE':
                decls.append(self.parse_file())
            elif self.cur().typ=='RULE':
                decls.append(self.parse_rule())
            elif self.cur().typ=='PROC':
                decls.append(self.parse_proc())
            else:
                self.error(f"Unexpected token {self.cur()}")
        return Program(name,decls)
    def parse_type(self):
        self.eat('TYPE'); name=self.eat('ID').val; self.eat('EQ')
        # enumType: alt | alt|alt
        variants=[self.eat('ID').val]
        while self.cur().typ=='OP' and self.cur().val=='|':
            self.eat('OP'); variants.append(self.eat('ID').val)
        self.eat('DOT')
        return TypeDecl(name,variants)
    def parse_record(self):
        self.eat('RECORD'); name=self.eat('ID').val; self.eat('LBR')
        fields=[]
        while self.cur().typ!='RBR':
            fname=self.eat('ID').val; self.eat('COL')
            ftype=self.parse_type_ref(); self.eat('DOT')
            fields.append(Field(fname,ftype))
        self.eat('RBR'); self.eat('DOT')
        return RecordDecl(name,fields)
    def parse_type_ref(self):
        t=self.cur()
        if t.typ=='CHAR':
            self.eat('CHAR'); self.eat('LP'); n=int(self.eat('NUMBER').val); self.eat('RP'); return ('CHAR',n)
        if t.typ=='NUM':
            self.eat('NUM'); self.eat('LP'); p=int(self.eat('NUMBER').val)
            if self.cur().typ== 'COMMA':
                self.eat('COMMA'); s=int(self.eat('NUMBER').val)
            else: s=0
            self.eat('RP'); return ('NUM',p,s)
        # user type
        name=self.eat('ID').val; return ('USER',name)
    def parse_file(self):
        self.eat('FILE'); name=self.eat('ID').val; self.eat('USING'); storage=self.eat('ID').val
        self.eat('KEY'); keyfields=[]
        keyfields.append(self.eat('ID').val); self.eat('LP'); self.eat('NUMBER'); self.eat('RP')
        while self.cur().typ=='COMMA':
            self.eat('COMMA'); keyfields.append(self.eat('ID').val); self.eat('LP'); self.eat('NUMBER'); self.eat('RP')
        self.eat('DOT')
        return FileDecl(name,storage,keyfields)
    def parse_rule(self):
        self.eat('RULE'); name=self.eat('ID').val; self.eat('LP')
        params=[]
        if self.cur().typ!='RP':
            params.append(self.parse_param())
            while self.cur().typ=='COMMA':
                self.eat('COMMA'); params.append(self.parse_param())
        self.eat('RP'); self.eat('EQ')
        expr=self.parse_expr(); self.eat('DOT')
        return RuleDecl(name,params,expr)
    def parse_param(self):
        n=self.eat('ID').val; self.eat('COL'); t=self.parse_type_ref(); return Param(n,t)
    def parse_proc(self):
        self.eat('PROC'); name=self.eat('ID').val; self.eat('LP')
        params=[]
        if self.cur().typ!='RP':
            params.append(self.parse_param())
            while self.cur().typ=='COMMA':
                self.eat('COMMA'); params.append(self.parse_param())
        self.eat('RP'); self.eat('EQ')
        body=[]
        while self.cur().typ!='DOT':
            body.append(self.parse_stmt())
        self.eat('DOT')
        return ProcDecl(name,params,body)
    def parse_stmt(self):
        t=self.cur()
        if t.typ=='REQUIRE':
            self.eat('REQUIRE'); e=self.parse_expr(); self.eat('DOT'); return Require(e)
        if t.typ=='LOAD':
            self.eat('LOAD'); rec=self.eat('ID').val; self.eat('LP')
            keys=[]
            if self.cur().typ!='RP':
                keys.append(self.parse_expr())
                while self.cur().typ=='COMMA':
                    self.eat('COMMA'); keys.append(self.parse_expr())
            self.eat('RP'); self.eat('AS'); alias=self.eat('ID').val; self.eat('DOT'); return Load(rec,keys,alias)
        if t.typ=='SAVE':
            self.eat('SAVE'); alias=self.eat('ID').val; self.eat('DOT'); return Save(alias)
        if t.typ=='IF':
            self.eat('IF'); cond=self.parse_expr(); self.eat('THEN')
            thenSt=[]
            while self.cur().typ not in ('ELSE','ENDIF'):
                thenSt.append(self.parse_stmt())
            elseSt=[]
            if self.cur().typ=='ELSE':
                self.eat('ELSE')
                while self.cur().typ!='ENDIF':
                    elseSt.append(self.parse_stmt())
            self.eat('ENDIF'); self.eat('DOT'); return IfStmt(cond,thenSt,elseSt)
        if t.typ=='FAIL':
            self.eat('FAIL'); msg=self.eat('STRING').val; self.eat('DOT'); return Fail(msg)
        # assign: ident := expr .
        if t.typ=='ID':
            left=self.eat('ID').val
            if self.cur().typ=='DOT':
                self.eat('DOT'); fld=self.eat('ID').val; left=(left,fld)
            self.eat('EQ'); expr=self.parse_expr(); self.eat('DOT'); return Assign(left,expr)
        self.error(f"Unknown stmt {t}")
    def parse_expr(self):
        # only simple binary ops and IN
        left=self.parse_primary()
        if self.cur().typ=='OP':
            op=self.eat('OP').val; right=self.parse_primary(); return BinOp(op,left,right)
        if self.cur().typ=='IN':
            self.eat('IN'); self.eat('LP'); vals=[]
            vals.append(self.parse_primary())
            while self.cur().typ=='COMMA':
                self.eat('COMMA'); vals.append(self.parse_primary())
            self.eat('RP'); return InExpr(left,vals)
        return left
    def parse_primary(self):
        t=self.cur()
        if t.typ=='ID':
            # could be enum literal Type.Variant
            id1=self.eat('ID').val
            if self.cur().typ== 'DOT':
                self.eat('DOT'); id2=self.eat('ID').val; return EnumLit(id1,id2)
            if self.cur().typ== 'DOT': pass
            return Ident(id1)
        if t.typ=='STRING':
            v=self.eat('STRING').val; return Literal(v[1:-1])
        if t.typ=='NUMBER':
            v=self.eat('NUMBER').val
            if '.' in v: return Literal(float(v))
            return Literal(int(v))
        if t.typ=='LP':
            self.eat('LP'); e=self.parse_expr(); self.eat('RP'); return e
        self.error(f"Unexpected primary {t}")

# ---------------------------------------------------------------------------
# Type system & Semantic Analyzer -> Business IR builder
# ---------------------------------------------------------------------------
# IR classes (compact)
class IrType: pass
class IrChar(IrType):
    def __init__(self,n): self.n=n
class IrNum(IrType):
    def __init__(self,p,s): self.p=p; self.s=s
class IrEnum(IrType):
    def __init__(self,name,variants): self.name=name; self.variants=variants
class IrRecordType(IrType):
    def __init__(self,name,fields): self.name=name; self.fields=fields

class IrField:
    def __init__(self,name,typ): self.name=name; self.typ=typ

class IrFile:
    def __init__(self,name,storage,keyfields): self.name=name; self.storage=storage; self.keyfields=keyfields

class IrRule:
    def __init__(self,name,params,expr): self.name=name; self.params=params; self.expr=expr

class IrProc:
    def __init__(self,name,params,requires,body,effects):
        self.name=name; self.params=params; self.requires=requires; self.body=body; self.effects=effects

class IrStateTransition:
    def __init__(self,record,field,froms,to,guard):
        self.record=record; self.field=field; self.froms=froms; self.to=to; self.guard=guard

# Simple symbol tables
class Context:
    def __init__(self):
        self.types: Dict[str,IrType] = {}
        self.records: Dict[str,IrRecordType] = {}
        self.files: Dict[str,IrFile] = {}
        self.rules: Dict[str,IrRule] = {}
        self.procs: Dict[str,IrProc] = {}
        # builtin primitives
        self.types['CHAR']=IrChar
        self.types['NUM']=IrNum

# Helpers to convert AST types -> IR types
def ast_type_to_ir(ctx:Context, t):
    kind = t[0]
    if kind=='CHAR': return IrChar(t[1])
    if kind=='NUM': return IrNum(t[1],t[2])
    if kind=='USER':
        name=t[1]
        if name in ctx.types and isinstance(ctx.types[name],IrEnum):
            return ctx.types[name]
        if name in ctx.records:
            return ctx.records[name]
        raise TypeError(f"Unknown user type {name}")
    raise TypeError("Unknown type")

# Semantic analyzer: build IR
def build_ir(ast:Program) -> Tuple[Context, List[IrProc]]:
    ctx=Context()
    # first pass: types and records and files
    for d in ast.decls:
        if isinstance(d,TypeDecl):
            ctx.types[d.name]=IrEnum(d.name,d.variants)
        elif isinstance(d,RecordDecl):
            fields=[IrField(f.name, None) for f in d.fields]
            # temporarily store types as raw; resolve later
            ctx.records[d.name]=IrRecordType(d.name,fields)
            # store field raw types in a map
            ctx.records[d.name].__raw_fields = d.fields
        elif isinstance(d,FileDecl):
            ctx.files[d.name]=IrFile(d.name,d.storage,d.keyfields)
    # resolve record field types
    for rname, r in ctx.records.items():
        raw = getattr(r,'__raw_fields',[])
        r.fields=[]
        for rf in raw:
            irt = ast_type_to_ir(ctx, rf.typ)
            r.fields.append(IrField(rf.name,irt))
    # second pass: rules and procs
    ir_procs=[]
    for d in ast.decls:
        if isinstance(d,RuleDecl):
            # params: list of Param
            params=[(p.name, ast_type_to_ir(ctx,p.typ)) for p in d.params]
            ir = IrRule(d.name, params, d.expr)
            ctx.rules[d.name]=ir
        if isinstance(d,ProcDecl):
            params=[(p.name, ast_type_to_ir(ctx,p.typ)) for p in d.params]
            # body -> simple translation to IR statements (we keep AST stmts but validate)
            requires=[]; body=[]; effects=[]
            for s in d.body:
                if isinstance(s,Require):
                    requires.append(s.expr)
                else:
                    body.append(s)
            proc = IrProc(d.name, params, requires, body, effects)
            ctx.procs[d.name]=proc
            ir_procs.append(proc)
    # basic semantic checks
    # RULE purity: ensure no LOAD/SAVE/FAIL in rule expr (we only allow expressions)
    for r in ctx.rules.values():
        # naive: assume expr is pure
        pass
    return ctx, ir_procs

# ---------------------------------------------------------------------------
# IR -> COBOL codegen (template-based, minimal)
# ---------------------------------------------------------------------------
def emit_cobol_program(ctx:Context, proc:IrProc, files_map:Dict[str,IrFile], records_map:Dict[str,IrRecordType]):
    # Only supports single-record param that maps to a file record
    prog = []
    pid = proc.name.upper()
    prog.append(f"IDENTIFICATION DIVISION.\nPROGRAM-ID. {pid}.\n")
    # ENV + FILE-CONTROL
    prog.append("ENVIRONMENT DIVISION.\nINPUT-OUTPUT SECTION.\nFILE-CONTROL.\n")
    # emit files used by proc by scanning LOAD/SAVE statements
    used_files=set()
    for s in proc.body:
        if isinstance(s,Load):
            used_files.add(s.recname)
    for fname in used_files:
        f = files_map[fname]
        prog.append(f"    SELECT {fname.upper()}-FILE ASSIGN TO {f.storage}\n")
        prog.append("        ORGANIZATION IS INDEXED\n        ACCESS MODE IS DYNAMIC\n        RECORD KEY IS {0}-KEY\n        FILE STATUS IS {0}-STATUS.\n".format(fname.upper()))
    # DATA DIVISION
    prog.append("\nDATA DIVISION.\nFILE SECTION.\n")
    for fname in used_files:
        rec = records_map[fname]
        prog.append(f"FD {fname.upper()}-FILE.\n01 {fname.upper()}-REC.\n")
        for fld in rec.fields:
            if isinstance(fld.typ,IrChar):
                prog.append(f"   05 {fld.name.upper():<20} PIC X({fld.typ.n}).\n")
            elif isinstance(fld.typ,IrNum):
                # map to display numeric for simplicity
                p=fld.typ.p; s=fld.typ.s
                intd = p - s
                pic = f"S{intd}({intd})V{('9'*s) if s>0 else ''}"
                # fallback to generic
                pic = f"S9({p})V9({s})"
                prog.append(f"   05 {fld.name.upper():<20} PIC {pic}.\n")
            elif isinstance(fld.typ,IrEnum):
                prog.append(f"   05 {fld.name.upper():<20} PIC X(12).\n")
            else:
                prog.append(f"   05 {fld.name.upper():<20} PIC X(32).\n")
    # WORKING-STORAGE
    prog.append("\nWORKING-STORAGE SECTION.\n01 WS-STATUS PIC X(02).\n")
    # LINKAGE
    prog.append("\nLINKAGE SECTION.\n")
    for pname, ptype in proc.params:
        # map param types to PICs
        if isinstance(ptype,IrRecordType):
            # expand fields as linkage
            for fld in ptype.fields:
                if isinstance(fld.typ,IrChar):
                    prog.append(f"01 LK-{fld.name.upper():<20} PIC X({fld.typ.n}).\n")
                elif isinstance(fld.typ,IrNum):
                    prog.append(f"01 LK-{fld.name.upper():<20} PIC S9({fld.typ.p})V9({fld.typ.s}).\n")
                else:
                    prog.append(f"01 LK-{fld.name.upper():<20} PIC X(32).\n")
        else:
            if isinstance(ptype,IrChar):
                prog.append(f"01 LK-{pname.upper():<20} PIC X({ptype.n}).\n")
            elif isinstance(ptype,IrNum):
                prog.append(f"01 LK-{pname.upper():<20} PIC S9({ptype.p})V9({ptype.s}).\n")
            else:
                prog.append(f"01 LK-{pname.upper():<20} PIC X(32).\n")
    # PROCEDURE DIVISION
    prog.append("\nPROCEDURE DIVISION USING ")
    prog.append(', '.join([pname.upper() for pname,_ in proc.params]) + ".\n\n")
    # Emit requires as IF checks
    for req in proc.requires:
        # naive: only support simple IN checks and not equals
        if isinstance(req,InExpr):
            left = req.left
            if isinstance(left,FieldRef):
                prog.append(f"    IF {left.alias.upper()}-{left.field.upper()} NOT IN (")
                vals = []
                for v in req.vals:
                    if isinstance(v,EnumLit):
                        vals.append(f"'{v.variant}'")
                    elif isinstance(v,Literal):
                        vals.append(f"'{v.val}'")
                prog.append(','.join(vals)+")\n")
                prog.append("       MOVE 'BADSTATE' TO WS-STATUS\n       GOBACK\n    END-IF\n")
        elif isinstance(req,BinOp) and req.op=='!=':
            # left != right
            l=req.l; r=req.r
            if isinstance(l,FieldRef) and isinstance(r,EnumLit):
                prog.append(f"    IF {l.alias.upper()}-{l.field.upper()} = '{r.variant}'\n")
                prog.append("       MOVE 'ALREADYRT' TO WS-STATUS\n       GOBACK\n    END-IF\n")
    # Body: handle LOAD/Assign/SAVE/Fail/If
    for s in proc.body:
        if isinstance(s,Load):
            # READ file by key
            key_exprs = s.keys
            # assume keys are Ident or Literal
            keyvals=[]
            for ke in key_exprs:
                if isinstance(ke,Literal): keyvals.append(str(ke.val))
                elif isinstance(ke,Ident): keyvals.append(ke.name.upper())
                elif isinstance(ke,FieldRef): keyvals.append(f"{ke.alias.upper()}-{ke.field.upper()}")
                else: keyvals.append('0')
            prog.append(f"    MOVE {keyvals[0]} TO {s.recname.upper()}-KEY\n")
            prog.append(f"    READ {s.recname.upper()}-FILE\n        INVALID KEY\n            MOVE 'NOTFOUND' TO WS-STATUS\n            GOBACK\n    END-READ\n")
        elif isinstance(s,Assign):
            tgt = s.target
            if isinstance(tgt,tuple):
                alias, fld = tgt
                # expr simple literal or enum
                if isinstance(s.expr,EnumLit):
                    prog.append(f"    MOVE '{s.expr.variant}' TO {alias.upper()}-{fld.upper()}\n")
                elif isinstance(s.expr,Literal):
                    prog.append(f"    MOVE '{s.expr.val}' TO {alias.upper()}-{fld.upper()}\n")
                elif isinstance(s.expr,FieldRef):
                    prog.append(f"    MOVE {s.expr.alias.upper()}-{s.expr.field.upper()} TO {alias.upper()}-{fld.upper()}\n")
            else:
                # simple var assign
                if isinstance(s.expr,Literal):
                    prog.append(f"    MOVE '{s.expr.val}' TO {tgt.upper()}\n")
        elif isinstance(s,Save):
            prog.append(f"    REWRITE {s.alias.upper()}-REC\n        INVALID KEY\n            MOVE 'DBERR' TO WS-STATUS\n            GOBACK\n    END-REWRITE\n")
        elif isinstance(s,Fail):
            prog.append(f"    MOVE 'FAIL' TO WS-STATUS\n    GOBACK\n")
        elif isinstance(s,IfStmt):
            # naive: only simple condition checks
            cond = s.cond
            if isinstance(cond,BinOp) and cond.op=='=' and isinstance(cond.l,FieldRef) and isinstance(cond.r,Literal):
                prog.append(f"    IF {cond.l.alias.upper()}-{cond.l.field.upper()} = '{cond.r.val}'\n")
                for ss in s.thenStmts:
                    if isinstance(ss,Fail):
                        prog.append(f"       MOVE 'FAIL' TO WS-STATUS\n       GOBACK\n")
                prog.append("    END-IF\n")
    prog.append("\n    MOVE 'OK' TO WS-STATUS\n    GOBACK.\n")
    return ''.join(prog)

# ---------------------------------------------------------------------------
# IR -> Prolog codegen (simple)
# ---------------------------------------------------------------------------
def emit_prolog(ctx:Context, proc:IrProc, records_map:Dict[str,IrRecordType]):
    out=[]
    # facts: record predicate signatures
    for rname, rec in records_map.items():
        fields = ','.join([f.name for f in rec.fields])
        # we don't emit facts here; backend expects facts from DB
        out.append(f"% record {rname}({fields})\n")
    # rules: map ctx.rules
    for rname, rule in ctx.rules.items():
        # naive: assume single param and IN expression
        expr = rule.expr
        if isinstance(expr,InExpr):
            left = expr.left
            vals = [v.variant if isinstance(v,EnumLit) else (v.val if isinstance(v,Literal) else str(v)) for v in expr.vals]
            out.append(f"{rname}({left.alias if isinstance(left,FieldRef) else left.name}) :-\n")
            conds = ' ; '.join([f"{left.alias if isinstance(left,FieldRef) else left.name} = {v.lower()}" for v in vals])
            out.append(f"    ({conds}).\n")
    # proc semantics: produce relation return_item(Item,Reason,Result)
    # naive mapping: find LOAD/Assign/Save pattern
    out.append(f"\n% proc {proc.name}\n")
    # produce clauses for success and errors for the example pattern
    # This is a small generator: detect LOAD then state checks then assign to state RETURNED
    # We'll emit a generic clause
    out.append(f"{proc.name}(Item, Reason, Result) :-\n")
    out.append(f"    Item = item(Company,Batch,Entry,State,Amount,OldReason),\n")
    out.append(f"    ( State = posted ; State = settled ),\n")
    out.append(f"    State \\= returned,\n")
    out.append(f"    Result = item(Company,Batch,Entry,returned,Amount,Reason).\n\n")
    # error clauses
    out.append(f"{proc.name}_error(notfound) :- \\+ item(_,_,_,_,_,_).\n")
    out.append(f"{proc.name}_error(badstate) :- item(_,_,_,State,_,_), \\+ (State = posted ; State = settled).\n")
    out.append(f"{proc.name}_error(alreadyrt) :- item(_,_,_,returned,_,_).\n")
    return ''.join(out)

# ---------------------------------------------------------------------------
# IR -> Mercury codegen (very small)
# ---------------------------------------------------------------------------
def emit_mercury(ctx:Context, proc:IrProc, records_map:Dict[str,IrRecordType]):
    out=[]
    out.append(":- module funnel_generated.\n:- interface.\n:- import_module io.\n\n")
    out.append(":- type state ---> new ; posted ; settled ; returned.\n\n")
    # item type
    out.append(":- type item ---> item(string, string, string, state, float, string).\n\n")
    out.append(":- pred return_item(item::in, string::in, item::out) is det.\n\n")
    out.append(":- implementation.\n\n")
    out.append("return_item(Item, Reason, Result) :-\n")
    out.append("    ( if Item = item(C,B,E,State,A,_) then\n")
    out.append("        ( if (State = posted ; State = settled), State \\= returned then\n")
    out.append("            Result = item(C,B,E,returned,A,Reason)\n")
    out.append("          else\n")
    out.append("            Result = Item\n")
    out.append("        )\n")
    out.append("      else\n")
    out.append("        Result = Item\n")
    out.append("    ).\n")
    return ''.join(out)

# ---------------------------------------------------------------------------
# Small driver & example
# ---------------------------------------------------------------------------
EXAMPLE = r'''
PROGRAM ach_return.

TYPE State = NEW | POSTED | SETTLED | RETURNED.

RECORD Item {
    company : CHAR(3).
    batch   : CHAR(10).
    entry   : CHAR(15).
    state   : State.
    amount  : NUM(13,2).
    reason  : CHAR(3).
}.

FILE achitem USING ACHITEM KEY company(3), batch(10), entry(15).

RULE returnable(item : Item) = item.state IN (State.POSTED, State.SETTLED).
IDENTIFICATION DIVISION.
                                                                                  PROGRAM-ID. ACHRTRN.
                                                                                  AUTHOR.     JESSICA+COPILOT.
                                                                                  ENVIRONMENT DIVISION.
                                                                                  CONFIGURATION SECTION.
                                                                                  SOURCE-COMPUTER. IBM-Z.
                                                                                  OBJECT-COMPUTER. IBM-Z.
                                                                           
                                                                                  INPUT-OUTPUT SECTION.
                                                                                  FILE-CONTROL.
                                                                                      SELECT ACHITEM-FILE ASSIGN TO ACHITEM
                                                                                          ORGANIZATION IS INDEXED
                                                                                          ACCESS MODE IS DYNAMIC
                                                                                          RECORD KEY IS AI-KEY
                                                                                          FILE STATUS IS AI-STATUS.
                                                                           
                                                                                      SELECT ACHRETLOG-FILE ASSIGN TO ACHRETLOG
                                                                                          ORGANIZATION IS INDEXED
                                                                                          ACCESS MODE IS DYNAMIC
                                                                                          RECORD KEY IS AR-KEY
                                                                                          FILE STATUS IS AR-STATUS.
                                                                           
                                                                                  DATA DIVISION.
                                                                                  FILE SECTION.
                                                                           
                                                                                  FD  ACHITEM-FILE.
                                                                                  01  ACHITEM-REC.
                                                                                      05 AI-KEY.
                                                                                         10 AI-COMPANY            PIC X(03).
                                                                                         10 AI-BATCH-ID           PIC X(10).
                                                                                         10 AI-ENTRY-ID           PIC X(15).
                                                                                      05 AI-RAIL-CODE             PIC X(08).
                                                                                      05 AI-ORIG-TRACE-NO         PIC X(15).
                                                                                      05 AI-ORIG-DFI              PIC X(09).
                                                                                      05 AI-ORIG-ACCOUNT          PIC X(17).
                                                                                      05 AI-ORIG-AMOUNT           PIC S9(13)V99 COMP-3.
                                                                                      05 AI-ORIG-DRCR-FLAG        PIC X(01). *> 'D' or 'C'
                                                                                      05 AI-CURRENCY              PIC X(03).
                                                                                      05 AI-STATE                 PIC X(12). *> NEW/POSTED/SETTLED/RETURNED/RETURN_POSTED/CLOSED
                                                                                      05 AI-SETTLEMENT-DATE       PIC X(08). *> YYYYMMDD
                                                                                      05 AI-ORIG-EFF-DATE         PIC X(08).
                                                                                      05 AI-ORIG-ENTRY-DESC       PIC X(10).
                                                                                      05 AI-ORIG-SEC-CODE         PIC X(03).
                                                                                      05 AI-ORIG-ENTRY-CLASS      PIC X(03).
                                                                                      05 AI-ORIG-ADDENDA          PIC X(94).
                                                                                      05 AI-RETURN-REASON         PIC X(03). *> NACHA R01/R03/etc
                                                                                      05 AI-RETURN-TS             PIC X(26). *> ISO TS
                                                                                      05 AI-RETURN-USER           PIC X(10).
                                                                                      05 AI-RETURN-CHANNEL        PIC X(08).
                                                                                      05 AI-RETURN-LEDGER-SEQ     PIC 9(09).
                                                                                      05 AI-LAST-UPD-TS           PIC X(26).
                                                                           
                                                                                  FD  ACHRETLOG-FILE.
                                                                                  01  ACHRETLOG-REC.
                                                                                      05 AR-KEY.
                                                                                         10 AR-COMPANY            PIC X(03).
                                                                                         10 AR-BATCH-ID           PIC X(10).
                                                                                         10 AR-ENTRY-ID           PIC X(15).
                                                                                         10 AR-LOG-SEQ            PIC 9(09).
                                                                                      05 AR-EVENT-CODE            PIC X(12). *> RET_REQ/RET_FAIL/RET_POST/RET_CLOSE
                                                                                      05 AR-EVENT-TS              PIC X(26).
                                                                                      05 AR-USER-ID               PIC X(10).
                                                                                      05 AR-CHANNEL               PIC X(08).
                                                                                      05 AR-REASON-CODE           PIC X(03).
                                                                                      05 AR-DETAIL                PIC X(256).
                                                                           
                                                                                  WORKING-STORAGE SECTION.
                                                                           
                                                                                  01  WS-PROGRAM-NAME            PIC X(08) VALUE 'ACHRTRN'.
                                                                                  01  WS-RUN-MODE                PIC X(01) VALUE 'B'. *> B=batch, O=online
                                                                           
                                                                                  01  AI-STATUS                  PIC X(02) VALUE SPACES.
                                                                                  01  AR-STATUS                  PIC X(02) VALUE SPACES.
                                                                           
                                                                                  01  WS-RETURN-REQUEST.
                                                                                      05 WR-COMPANY              PIC X(03).
                                                                                      05 WR-BATCH-ID             PIC X(10).
                                                                                      05 WR-ENTRY-ID             PIC X(15).
                                                                                      05 WR-USER-ID              PIC X(10).
                                                                                      05 WR-CHANNEL              PIC X(08).
                                                                                      05 WR-REASON-CODE          PIC X(03).
                                                                           
                                                                                  01  WS-RETURN-RESPONSE.
                                                                                      05 WRS-SUCCESS             PIC X(01). *> 'Y' or 'N'
                                                                                      05 WRS-ERROR-CODE          PIC X(08).
                                                                                      05 WRS-ERROR-MSG           PIC X(80).
                                                                                      05 WRS-LEDGER-SEQ          PIC 9(09).
                                                                           
                                                                                  01  WS-TIMESTAMP               PIC X(26).
                                                                                  01  WS-LOG-SEQ                 PIC 9(09) VALUE 0.
                                                                           
                                                                                  01  WS-STATE-TARGET            PIC X(12).
                                                                           
                                                                                  01  WS-REASON-VALID            PIC X(01) VALUE 'N'.
                                                                           
                                                                                  01  WS-RETURNABLE-STATE        PIC X(12).
                                                                           
                                                                                  01  WS-ABEND-FLAG              PIC X(01) VALUE 'N'.
                                                                           
                                                                                  01  WS-DISPLAY-MSG             PIC X(80).
                                                                           
                                                                                  01  FILLER REDEFINES WS-TIMESTAMP.
                                                                                      05 WS-TS-YYYY              PIC X(04).
                                                                                      05 WS-TS-MM                PIC X(02).
                                                                                      05 WS-TS-DD                PIC X(02).
                                                                                      05 WS-TS-T                 PIC X(01).
                                                                                      05 WS-TS-HH                PIC X(02).
                                                                                      05 WS-TS-MI                PIC X(02).
                                                                                      05 WS-TS-SS                PIC X(02).
                                                                                      05 WS-TS-DOT               PIC X(01).
                                                                                      05 WS-TS-MSEC              PIC X(03).
                                                                                      05 WS-TS-Z                 PIC X(01).
                                                                                      05 WS-TS-OFFSET            PIC X(06).
                                                                           
                                                                                  01  WS-REASON-TABLE.
                                                                                      05 WS-REASON-ENTRY OCCURS 20 TIMES INDEXED BY REASON-IDX.
                                                                                         10 WS-REASON-CODE       PIC X(03).
                                                                                         10 WS-REASON-DESC       PIC X(40).
                                                                           
                                                                                  01  WS-INIT-REASONS-SW         PIC X(01) VALUE 'N'.
                                                                           
                                                                                  LINKAGE SECTION.
                                                                                  01  LK-RETURN-REQUEST.
                                                                                      05 LK-COMPANY              PIC X(03).
                                                                                      05 LK-BATCH-ID             PIC X(10).
                                                                                      05 LK-ENTRY-ID             PIC X(15).
                                                                                      05 LK-USER-ID              PIC X(10).
                                                                                      05 LK-CHANNEL              PIC X(08).
                                                                                      05 LK-REASON-CODE          PIC X(03).
                                                                           
                                                                                  01  LK-RETURN-RESPONSE.
                                                                                      05 LK-SUCCESS              PIC X(01).
                                                                                      05 LK-ERROR-CODE           PIC X(08).
                                                                                      05 LK-ERROR-MSG            PIC X(80).
                                                                                      05 LK-LEDGER-SEQ           PIC 9(09).
                                                                           
                                                                                  PROCEDURE DIVISION USING LK-RETURN-REQUEST LK-RETURN-RESPONSE.
                                                                           
                                                                                  MAIN-SECTION.
                                                                                      PERFORM INIT-SECTION
                                                                                      PERFORM LOAD-REQUEST
                                                                                      PERFORM PROCESS-RETURN
                                                                                      PERFORM BUILD-RESPONSE
                                                                                      GOBACK.
                                                                           
                                                                                  INIT-SECTION.
                                                                                      IF WS-INIT-REASONS-SW = 'N'
                                                                                         PERFORM INIT-REASON-TABLE
                                                                                         MOVE 'Y' TO WS-INIT-REASONS-SW
                                                                                      END-IF
                                                                           
                                                                                      MOVE 'N' TO WRS-SUCCESS
                                                                                      MOVE SPACES TO WRS-ERROR-CODE WRS-ERROR-MSG
                                                                                      MOVE ZEROES TO WRS-LEDGER-SEQ
                                                                           
                                                                                      OPEN I-O ACHITEM-FILE
                                                                                      IF AI-STATUS NOT = '00'
                                                                                         MOVE 'Y' TO WS-ABEND-FLAG
                                                                                         MOVE 'FILEOPEN' TO WRS-ERROR-CODE
                                                                                         MOVE 'ACHITEM open failed' TO WRS-ERROR-MSG
                                                                                         PERFORM ABEND-SECTION
                                                                                      END-IF
                                                                           
                                                                                      OPEN I-O ACHRETLOG-FILE
                                                                                      IF AR-STATUS NOT = '00'
                                                                                         MOVE 'Y' TO WS-ABEND-FLAG
                                                                                         MOVE 'FILEOPEN' TO WRS-ERROR-CODE
                                                                                         MOVE 'ACHRETLOG open failed' TO WRS-ERROR-MSG
                                                                                         PERFORM ABEND-SECTION
                                                                                      END-IF
                                                                           
                                                                                      PERFORM GET-CURRENT-TIMESTAMP.
                                                                           
                                                                                  LOAD-REQUEST.
                                                                                      MOVE LK-COMPANY     TO WR-COMPANY
                                                                                      MOVE LK-BATCH-ID    TO WR-BATCH-ID
                                                                                      MOVE LK-ENTRY-ID    TO WR-ENTRY-ID
                                                                                      MOVE LK-USER-ID     TO WR-USER-ID
                                                                                      MOVE LK-CHANNEL     TO WR-CHANNEL
                                                                                      MOVE LK-REASON-CODE TO WR-REASON-CODE.
                                                                           
                                                                                  PROCESS-RETURN.
                                                                                      PERFORM LOAD-ACH-ITEM
                                                                                      IF WRS-ERROR-CODE NOT = SPACES
                                                                                         PERFORM LOG-RETURN-FAIL
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      PERFORM VALIDATE-RETURN-ELIGIBILITY
                                                                                      IF WRS-ERROR-CODE NOT = SPACES
                                                                                         PERFORM LOG-RETURN-FAIL
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      PERFORM APPLY-STATE-TRANSITION
                                                                                      IF WRS-ERROR-CODE NOT = SPACES
                                                                                         PERFORM LOG-RETURN-FAIL
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      PERFORM PERSIST-ACH-ITEM
                                                                                      IF WRS-ERROR-CODE NOT = SPACES
                                                                                         PERFORM LOG-RETURN-FAIL
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      PERFORM LOG-RETURN-SUCCESS.
                                                                           
                                                                                  BUILD-RESPONSE.
                                                                                      MOVE WRS-SUCCESS    TO LK-SUCCESS
                                                                                      MOVE WRS-ERROR-CODE TO LK-ERROR-CODE
                                                                                      MOVE WRS-ERROR-MSG  TO LK-ERROR-MSG
                                                                                      MOVE WRS-LEDGER-SEQ TO LK-LEDGER-SEQ.
                                                                           
                                                                                  LOAD-ACH-ITEM.
                                                                                      MOVE WR-COMPANY  TO AI-COMPANY
                                                                                      MOVE WR-BATCH-ID TO AI-BATCH-ID
                                                                                      MOVE WR-ENTRY-ID TO AI-ENTRY-ID
                                                                           
                                                                                      READ ACHITEM-FILE
                                                                                          INVALID KEY
                                                                                              MOVE 'NOTFOUND' TO WRS-ERROR-CODE
                                                                                              MOVE 'ACH item not found' TO WRS-ERROR-MSG
                                                                                          NOT INVALID KEY
                                                                                              CONTINUE
                                                                                      END-READ.
                                                                           
                                                                                  VALIDATE-RETURN-ELIGIBILITY.
                                                                                      IF WRS-ERROR-CODE NOT = SPACES
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      *> Only SETTLED or POSTED items can be returned
                                                                                      IF AI-STATE = 'SETTLED'
                                                                                         MOVE 'SETTLED' TO WS-RETURNABLE-STATE
                                                                                      ELSE
                                                                                         IF AI-STATE = 'POSTED'
                                                                                            MOVE 'POSTED' TO WS-RETURNABLE-STATE
                                                                                         ELSE
                                                                                            MOVE 'BADSTATE' TO WRS-ERROR-CODE
                                                                                            MOVE 'Item state not returnable: ' TO WRS-ERROR-MSG
                                                                                            STRING AI-STATE DELIMITED BY SIZE
                                                                                                   INTO WRS-ERROR-MSG
                                                                                            EXIT PARAGRAPH
                                                                                         END-IF
                                                                                      END-IF
                                                                           
                                                                                      *> Prevent double return
                                                                                      IF AI-STATE = 'RETURNED'
                                                                                         MOVE 'ALREADYRT' TO WRS-ERROR-CODE
                                                                                         MOVE 'Item already returned' TO WRS-ERROR-MSG
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      *> Validate reason code
                                                                                      PERFORM CHECK-REASON-CODE
                                                                                      IF WS-REASON-VALID NOT = 'Y'
                                                                                         MOVE 'BADREASN' TO WRS-ERROR-CODE
                                                                                         MOVE 'Invalid return reason code' TO WRS-ERROR-MSG
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF.
                                                                           
                                                                                  APPLY-STATE-TRANSITION.
                                                                                      IF WRS-ERROR-CODE NOT = SPACES
                                                                                         EXIT PARAGRAPH
                                                                                      END-IF
                                                                           
                                                                                      *> State machine:
                                                                                      *> SETTLED -> RETURNED
                                                                                      *> POSTED  -> RETURNED
                                                                                      MOVE 'RETURNED' TO WS-STATE-TARGET
                                                                           
                                                                                      MOVE WS-STATE-TARGET TO AI-STATE
                                                                                      MOVE WR-REASON-CODE  TO AI-RETURN-REASON
                                                                                      MOVE WR-USER-ID      TO AI-RETURN-USER
                                                                                      MOVE WR-CHANNEL      TO AI-RETURN-CHANNEL
                                                                                      MOVE WS-TIMESTAMP    TO AI-RETURN-TS
                                                                                      MOVE WS-TIMESTAMP    TO AI-LAST-UPD-TS.
                                                                           
                                                                                      *> Ledger seq will be filled by downstream posting engine
                                                                                      MOVE ZEROES TO AI-RETURN-LEDGER-SEQ.
                                                                           
                                                                                  PERSIST-ACH-ITEM.
                                                                                      REWRITE ACHITEM-REC
                                                                                          INVALID KEY
                                                                                              MOVE 'DBERR' TO WRS-ERROR-CODE
                                                                                              MOVE 'ACH item rewrite failed' TO WRS-ERROR-MSG
                                                                                          NOT INVALID KEY
                                                                                              CONTINUE
                                                                                      END-REWRITE.
                                                                           
                                                                                  LOG-RETURN-FAIL.
                                                                                      PERFORM NEXT-LOG-SEQ
                                                                                      MOVE WR-COMPANY   TO AR-COMPANY
                                                                                      MOVE WR-BATCH-ID  TO AR-BATCH-ID
                                                                                      MOVE WR-ENTRY-ID  TO AR-ENTRY-ID
                                                                                      MOVE WS-LOG-SEQ   TO AR-LOG-SEQ
                                                                                      MOVE 'RET_FAIL'   TO AR-EVENT-CODE
                                                                                      MOVE WS-TIMESTAMP TO AR-EVENT-TS
                                                                                      MOVE WR-USER-ID   TO AR-USER-ID
                                                                                      MOVE WR-CHANNEL   TO AR-CHANNEL
                                                                                      MOVE WR-REASON-CODE TO AR-REASON-CODE
                                                                                      MOVE SPACES       TO AR-DETAIL
                                                                           
                                                                                      STRING 'Return failed: '
                                                                                             WRS-ERROR-CODE DELIMITED BY SIZE
                                                                                             ' - ' DELIMITED BY SIZE
                                                                                             WRS-ERROR-MSG DELIMITED BY SIZE
                                                                                             INTO AR-DETAIL
                                                                                      END-STRING
                                                                           
                                                                                      WRITE ACHRETLOG-REC
                                                                                          INVALID KEY
                                                                                              CONTINUE
                                                                                      END-WRITE.
                                                                           
                                                                                  LOG-RETURN-SUCCESS.
                                                                                      MOVE 'Y' TO WRS-SUCCESS
                                                                                      MOVE 'OK' TO WRS-ERROR-CODE
                                                                                      MOVE 'Return accepted' TO WRS-ERROR-MSG
                                                                           
                                                                                      PERFORM NEXT-LOG-SEQ
                                                                                      MOVE WR-COMPANY   TO AR-COMPANY
                                                                                      MOVE WR-BATCH-ID  TO AR-BATCH-ID
                                                                                      MOVE WR-ENTRY-ID  TO AR-ENTRY-ID
                                                                                      MOVE WS-LOG-SEQ   TO AR-LOG-SEQ
                                                                                      MOVE 'RET_REQ'    TO AR-EVENT-CODE
                                                                                      MOVE WS-TIMESTAMP TO AR-EVENT-TS
                                                                                      MOVE WR-USER-ID   TO AR-USER-ID
                                                                                      MOVE WR-CHANNEL   TO AR-CHANNEL
                                                                                      MOVE WR-REASON-CODE TO AR-REASON-CODE
                                                                                      MOVE SPACES       TO AR-DETAIL
                                                                           
                                                                                      STRING 'Return requested; state='
                                                                                             AI-STATE DELIMITED BY SIZE
                                                                                             ' reason=' DELIMITED BY SIZE
                                                                                             WR-REASON-CODE DELIMITED BY SIZE
                                                                                             INTO AR-DETAIL
                                                                                      END-STRING
                                                                           
                                                                                      WRITE ACHRETLOG-REC
                                                                                          INVALID KEY
                                                                                              CONTINUE
                                                                                      END-WRITE.
                                                                           
                                                                                  CHECK-REASON-CODE.
                                                                                      MOVE 'N' TO WS-REASON-VALID
                                                                                      SET REASON-IDX TO 1
                                                                                      PERFORM VARYING REASON-IDX FROM 1 BY 1
                                                                                              UNTIL REASON-IDX > 20
                                                                                         IF WS-REASON-CODE (REASON-IDX) = WR-REASON-CODE
                                                                                            MOVE 'Y' TO WS-REASON-VALID
                                                                                            EXIT PERFORM
                                                                                         END-IF
                                                                                      END-PERFORM.
                                                                           
                                                                                  INIT-REASON-TABLE.
                                                                                      MOVE 'R01' TO WS-REASON-CODE (1)
                                                                                      MOVE 'Insufficient funds' TO WS-REASON-DESC (1)
                                                                           
                                                                                      MOVE 'R03' TO WS-REASON-CODE (2)
                                                                                      MOVE 'No account/Unable to locate' TO WS-REASON-DESC (2)
                                                                           
                                                                                      MOVE 'R04' TO WS-REASON-CODE (3)
                                                                                      MOVE 'Invalid account number' TO WS-REASON-DESC (3)
                                                                           
                                                                                      MOVE 'R07' TO WS-REASON-CODE (4)
                                                                                      MOVE 'Authorization revoked' TO WS-REASON-DESC (4)
                                                                           
                                                                                      MOVE 'R08' TO WS-REASON-CODE (5)
                                                                                      MOVE 'Payment stopped' TO WS-REASON-DESC (5)
                                                                           
                                                                                      MOVE 'R10' TO WS-REASON-CODE (6)
                                                                                      MOVE 'Customer advises not authorized' TO WS-REASON-DESC (6)
                                                                           
                                                                                      MOVE 'R29' TO WS-REASON-CODE (7)
                                                                                      MOVE 'Corporate customer advises not authorized' TO WS-REASON-DESC (7)
                                                                           
                                                                                      *> Remaining entries left blank; extend as needed.
                                                                           
                                                                                  NEXT-LOG-SEQ.
                                                                                      ADD 1 TO WS-LOG-SEQ.
                                                                           
                                                                                  GET-CURRENT-TIMESTAMP.
                                                                                      *> Stub: in production, call system service or LE routine
                                                                                      MOVE '20260908T192700.000Z+0000' TO WS-TIMESTAMP.
                                                                           
                                                                                  ABEND-SECTION.
                                                                                      IF WS-ABEND-FLAG = 'Y'
                                                                                         DISPLAY 'ACHRTRN ABEND: ' WRS-ERROR-CODE ' ' WRS-ERROR-MSG
                                                                                         GOBACK
                                                                                      END-IF.
                                                                           **free
                                                                           ctl-opt
                                                                             dftactgrp(*no)
                                                                             actgrp('LEDGER')
                                                                             bnddir('LEDGERBNDDIR')
                                                                             option(*srcstmt : *nodebugio)
                                                                             alwnull(*usrctl);
                                                                           
                                                                           /*********************************************************************/
                                                                           /*  LEDREVSRV - Ledger Reversal Service Program                      */
                                                                           /*                                                                   */
                                                                           /*  Responsibilities:                                                */
                                                                           /*   - Validate original ledger entry for reversal eligibility       */
                                                                           /*   - Enforce idempotency (no double reversal)                      */
                                                                           /*   - Create balanced reversal entry                                */
                                                                           /*   - Persist reversal + audit trail                                */
                                                                           /*   - Return status + error codes to caller                         */
                                                                           /*********************************************************************/
                                                                           
                                                                           /*-------------------------------------------------------------------*/
                                                                           /*  Data structures: external formats for LEDGER and LEDGER_AUD      */
                                                                           /*-------------------------------------------------------------------*/
                                                                           
                                                                           dcl-f LEDGER    keyed usage(*update : *input : *output)
                                                                                           extdesc('LEDGER') extfile('LEDGER')
                                                                                           usropn;
                                                                           
                                                                           dcl-f LEDGER_AUD keyed usage(*output)
                                                                                           extdesc('LEDGER_AUD') extfile('LEDGER_AUD')
                                                                                           usropn;
                                                                           
                                                                           /* Key structure for LEDGER (example) */
                                                                           dcl-ds dsLedgerKey qualified;
                                                                             Company        char(3);
                                                                             LedgerDate     char(8);   // YYYYMMDD
                                                                             LedgerSeq      packed(9:0);
                                                                           end-ds;
                                                                           
                                                                           /* Core ledger record (simplified example) */
                                                                           dcl-ds dsLedgerRec qualified;
                                                                             Company        char(3);
                                                                             LedgerDate     char(8);
                                                                             LedgerSeq      packed(9:0);
                                                                             TxnId          char(36);
                                                                             TxnType        char(4);
                                                                             DrCrFlag       char(1);   // 'D' or 'C'
                                                                             Amount         packed(15:2);
                                                                             Currency       char(3);
                                                                             Status         char(1);   // 'N'=Normal, 'R'=Reversed, 'X'=Cancelled
                                                                             ParentSeq      packed(9:0); // link to original if this is reversal
                                                                             BookTs         timestamp;
                                                                             PostTs         timestamp;
                                                                             Channel        char(8);
                                                                             RailCode       char(8);
                                                                             UserId         char(10);
                                                                             ReversalCode   char(4);   // reason code
                                                                             ReversalTs     timestamp;
                                                                           end-ds;
                                                                           
                                                                           /* Audit record */
                                                                           dcl-ds dsAuditRec qualified;
                                                                             Company        char(3);
                                                                             LedgerDate     char(8);
                                                                             LedgerSeq      packed(9:0);
                                                                             AuditSeq       packed(9:0);
                                                                             EventCode      char(8);   // 'REV_REQ','REV_POST','REV_FAIL'
                                                                             EventTs        timestamp;
                                                                             TxnId          char(36);
                                                                             UserId         char(10);
                                                                             ReasonCode     char(4);
                                                                             Detail         char(256);
                                                                           end-ds;
                                                                           
                                                                           /*-------------------------------------------------------------------*/
                                                                           /*  Public API: LED_ReverseEntry                                     */
                                                                           /*-------------------------------------------------------------------*/
                                                                           
                                                                           /* Request structure */
                                                                           dcl-ds dsReverseReq qualified;
                                                                             Company        char(3);
                                                                             LedgerDate     char(8);
                                                                             LedgerSeq      packed(9:0);
                                                                             UserId         char(10);
                                                                             ReasonCode     char(4);
                                                                             Channel        char(8);
                                                                           end-ds;
                                                                           
                                                                           /* Response structure */
                                                                           dcl-ds dsReverseRsp qualified;
                                                                             Success        ind;
                                                                             ErrorCode      char(8);   // 'OK','NOTFOUND','ALREADYREV','BADSTATE','DBERR','VALERR'
                                                                             ErrorMsg       char(128);
                                                                             NewLedgerSeq   packed(9:0);
                                                                           end-ds;
                                                                           
                                                                           /* Prototype */
                                                                           dcl-pr LED_ReverseEntry extpgm('LEDREVSRV');
                                                                             pReq        likeds(dsReverseReq) const;
                                                                             pRsp        likeds(dsReverseRsp);
                                                                           end-pr;
                                                                           
                                                                           /* Implementation */
                                                                           dcl-pi LED_ReverseEntry;
                                                                             pReq        likeds(dsReverseReq) const;
                                                                             pRsp        likeds(dsReverseRsp);
                                                                           end-pi;
                                                                           
                                                                           /*-------------------------------------------------------------------*/
                                                                           /*  Local procedures                                                 */
                                                                           /*-------------------------------------------------------------------*/
                                                                           
                                                                           dcl-proc InitResponse;
                                                                             dcl-pi *n;
                                                                               req        likeds(dsReverseReq) const;
                                                                               rsp        likeds(dsReverseRsp);
                                                                             end-pi;
                                                                           
                                                                             rsp.Success    = *off;
                                                                             rsp.ErrorCode  = 'OK';
                                                                             rsp.ErrorMsg   = *blanks;
                                                                             rsp.NewLedgerSeq = 0;
                                                                           end-proc;
                                                                           
                                                                           dcl-proc LoadOriginalEntry;
                                                                             dcl-pi *n ind;
                                                                               req        likeds(dsReverseReq) const;
                                                                               rec        likeds(dsLedgerRec);
                                                                             end-pi;
                                                                           
                                                                             dsLedgerKey.Company    = req.Company;
                                                                             dsLedgerKey.LedgerDate = req.LedgerDate;
                                                                             dsLedgerKey.LedgerSeq  = req.LedgerSeq;
                                                                           
                                                                             chain dsLedgerKey LEDGER;
                                                                             if not %found(LEDGER);
                                                                               return *off;
                                                                             endif;
                                                                           
                                                                             rec.Company      = LEDGER.Company;
                                                                             rec.LedgerDate   = LEDGER.LedgerDate;
                                                                             rec.LedgerSeq    = LEDGER.LedgerSeq;
                                                                             rec.TxnId        = LEDGER.TxnId;
                                                                             rec.TxnType      = LEDGER.TxnType;
                                                                             rec.DrCrFlag     = LEDGER.DrCrFlag;
                                                                             rec.Amount       = LEDGER.Amount;
                                                                             rec.Currency     = LEDGER.Currency;
                                                                             rec.Status       = LEDGER.Status;
                                                                             rec.ParentSeq    = LEDGER.ParentSeq;
                                                                             rec.BookTs       = LEDGER.BookTs;
                                                                             rec.PostTs       = LEDGER.PostTs;
                                                                             rec.Channel      = LEDGER.Channel;
                                                                             rec.RailCode     = LEDGER.RailCode;
                                                                             rec.UserId       = LEDGER.UserId;
                                                                             rec.ReversalCode = LEDGER.ReversalCode;
                                                                             rec.ReversalTs   = LEDGER.ReversalTs;
                                                                           
                                                                             return *on;
                                                                           end-proc;
                                                                           
                                                                           dcl-proc ValidateReversalEligibility;
                                                                             dcl-pi *n ind;
                                                                               origRec    likeds(dsLedgerRec) const;
                                                                               rsp        likeds(dsReverseRsp);
                                                                             end-pi;
                                                                           
                                                                             select;
                                                                             when origRec.Status = 'R';
                                                                               rsp.ErrorCode = 'ALREADYREV';
                                                                               rsp.ErrorMsg  = 'Entry already reversed.';
                                                                               return *off;
                                                                           
                                                                             when origRec.Status = 'X';
                                                                               rsp.ErrorCode = 'BADSTATE';
                                                                               rsp.ErrorMsg  = 'Entry cancelled; reversal not allowed.';
                                                                               return *off;
                                                                           
                                                                             other;
                                                                               // OK for now; you can add more rules (age, rail, etc.)
                                                                             endsl;
                                                                           
                                                                             if origRec.Amount = 0;
                                                                               rsp.ErrorCode = 'VALERR';
                                                                               rsp.ErrorMsg  = 'Zero-amount entry cannot be reversed.';
                                                                               return *off;
                                                                             endif;
                                                                           
                                                                             return *on;
                                                                           end-proc;
                                                                           
                                                                           dcl-proc BuildReversalEntry;
                                                                             dcl-pi *n;
                                                                               req        likeds(dsReverseReq) const;
                                                                               origRec    likeds(dsLedgerRec) const;
                                                                               revRec     likeds(dsLedgerRec);
                                                                             end-pi;
                                                                           
                                                                             revRec = origRec;
                                                                           
                                                                             // New sequence will be assigned by DB trigger or separate allocator
                                                                             revRec.LedgerSeq    = 0;
                                                                             revRec.ParentSeq    = origRec.LedgerSeq;
                                                                             revRec.Status       = 'N';
                                                                             revRec.ReversalCode = req.ReasonCode;
                                                                             revRec.ReversalTs   = %timestamp();
                                                                           
                                                                             // Flip DR/CR and keep amount
                                                                             select;
                                                                             when origRec.DrCrFlag = 'D';
                                                                               revRec.DrCrFlag = 'C';
                                                                             when origRec.DrCrFlag = 'C';
                                                                               revRec.DrCrFlag = 'D';
                                                                             other;
                                                                               // Unknown flag; caller should have validated, but we guard anyway
                                                                               revRec.DrCrFlag = origRec.DrCrFlag;
                                                                             endsl;
                                                                           
                                                                             // Channel/User for reversal
                                                                             revRec.Channel = req.Channel;
                                                                             revRec.UserId  = req.UserId;
                                                                           
                                                                           end-proc;
                                                                           
                                                                           dcl-proc PersistReversal;
                                                                             dcl-pi *n ind;
                                                                               revRec     likeds(dsLedgerRec);
                                                                               newSeq     packed(9:0);
                                                                             end-pi;
                                                                           
                                                                             monitor;
                                                                               // Write reversal entry
                                                                               LEDGER.Company      = revRec.Company;
                                                                               LEDGER.LedgerDate   = revRec.LedgerDate;
                                                                               LEDGER.LedgerSeq    = revRec.LedgerSeq; // 0 if auto-assigned
                                                                               LEDGER.TxnId        = revRec.TxnId;
                                                                               LEDGER.TxnType      = revRec.TxnType;
                                                                               LEDGER.DrCrFlag     = revRec.DrCrFlag;
                                                                               LEDGER.Amount       = revRec.Amount;
                                                                               LEDGER.Currency     = revRec.Currency;
                                                                               LEDGER.Status       = revRec.Status;
                                                                               LEDGER.ParentSeq    = revRec.ParentSeq;
                                                                               LEDGER.BookTs       = %timestamp();
                                                                               LEDGER.PostTs       = %timestamp();
                                                                               LEDGER.Channel      = revRec.Channel;
                                                                               LEDGER.RailCode     = revRec.RailCode;
                                                                               LEDGER.UserId       = revRec.UserId;
                                                                               LEDGER.ReversalCode = revRec.ReversalCode;
                                                                               LEDGER.ReversalTs   = revRec.ReversalTs;
                                                                           
                                                                               write LEDGER;
                                                                           
                                                                               // If sequence is assigned by identity/trigger, re-read
                                                                               dsLedgerKey.Company    = LEDGER.Company;
                                                                               dsLedgerKey.LedgerDate = LEDGER.LedgerDate;
                                                                               dsLedgerKey.LedgerSeq  = LEDGER.LedgerSeq;
                                                                           
                                                                               chain dsLedgerKey LEDGER;
                                                                               if %found(LEDGER);
                                                                                 newSeq = LEDGER.LedgerSeq;
                                                                               else;
                                                                                 newSeq = revRec.LedgerSeq;
                                                                               endif;
                                                                           
                                                                               return *on;
                                                                           
                                                                             on-error;
                                                                               return *off;
                                                                             endmon;
                                                                           
                                                                           end-proc;
                                                                           
                                                                           dcl-proc MarkOriginalAsReversed;
                                                                             dcl-pi *n ind;
                                                                               origRec    likeds(dsLedgerRec);
                                                                               reason     char(4) const;
                                                                             end-pi;
                                                                           
                                                                             dsLedgerKey.Company    = origRec.Company;
                                                                             dsLedgerKey.LedgerDate = origRec.LedgerDate;
                                                                             dsLedgerKey.LedgerSeq  = origRec.LedgerSeq;
                                                                           
                                                                             chain dsLedgerKey LEDGER;
                                                                             if not %found(LEDGER);
                                                                               return *off;
                                                                             endif;
                                                                           
                                                                             LEDGER.Status       = 'R';
                                                                             LEDGER.ReversalCode = reason;
                                                                             LEDGER.ReversalTs   = %timestamp();
                                                                           
                                                                             update LEDGER;
                                                                           
                                                                             return *on;
                                                                           end-proc;
                                                                           
                                                                           dcl-proc WriteAuditEvent;
                                                                             dcl-pi *n ind;
                                                                               company     char(3) const;
                                                                               ledgerDate  char(8) const;
                                                                               ledgerSeq   packed(9:0) const;
                                                                               eventCode   char(8) const;
                                                                               userId      char(10) const;
                                                                               reasonCode  char(4) const;
                                                                               detail      char(256) const;
                                                                             end-pi;
                                                                           
                                                                             monitor;
                                                                               dsAuditRec.Company    = company;
                                                                               dsAuditRec.LedgerDate = ledgerDate;
                                                                               dsAuditRec.LedgerSeq  = ledgerSeq;
                                                                               dsAuditRec.AuditSeq   = 0; // identity/trigger or separate allocator
                                                                               dsAuditRec.EventCode  = eventCode;
                                                                               dsAuditRec.EventTs    = %timestamp();
                                                                               dsAuditRec.TxnId      = *blanks;
                                                                               dsAuditRec.UserId     = userId;
                                                                               dsAuditRec.ReasonCode = reasonCode;
                                                                               dsAuditRec.Detail     = detail;
                                                                           
                                                                               LEDGER_AUD.Company    = dsAuditRec.Company;
                                                                               LEDGER_AUD.LedgerDate = dsAuditRec.LedgerDate;
                                                                               LEDGER_AUD.LedgerSeq  = dsAuditRec.LedgerSeq;
                                                                               LEDGER_AUD.AuditSeq   = dsAuditRec.AuditSeq;
                                                                               LEDGER_AUD.EventCode  = dsAuditRec.EventCode;
                                                                               LEDGER_AUD.EventTs    = dsAuditRec.EventTs;
                                                                               LEDGER_AUD.TxnId      = dsAuditRec.TxnId;
                                                                               LEDGER_AUD.UserId     = dsAuditRec.UserId;
                                                                               LEDGER_AUD.ReasonCode = dsAuditRec.ReasonCode;
                                                                               LEDGER_AUD.Detail     = dsAuditRec.Detail;
                                                                           
                                                                               write LEDGER_AUD;
                                                                           
                                                                               return *on;
                                                                           
                                                                             on-error;
                                                                               return *off;
                                                                             endmon;
                                                                           
                                                                           end-proc;
                                                                           
                                                                           /*-------------------------------------------------------------------*/
                                                                           /*  Main entry: LED_ReverseEntry                                     */
                                                                           /*-------------------------------------------------------------------*/
                                                                           
                                                                           dcl-s origRec likeds(dsLedgerRec);
                                                                           dcl-s revRec  likeds(dsLedgerRec);
                                                                           dcl-s newSeq  packed(9:0);
                                                                           
                                                                           InitResponse(pReq : pRsp);
                                                                           
                                                                           /* Open files once per call; you can move to *INZSR if you prefer */
                                                                           open LEDGER;
                                                                           open LEDGER_AUD;
                                                                           
                                                                           /* Load original entry */
                                                                           if not LoadOriginalEntry(pReq : origRec);
                                                                             pRsp.ErrorCode = 'NOTFOUND';
                                                                             pRsp.ErrorMsg  = 'Original ledger entry not found.';
                                                                             WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                                                                                             'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                                                                                             'Reversal failed: NOTFOUND');
                                                                             return;
                                                                           endif;
                                                                           
                                                                           /* Validate eligibility */
                                                                           if not ValidateReversalEligibility(origRec : pRsp);
                                                                             WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                                                                                             'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                                                                                             'Reversal failed: ' + %trim(pRsp.ErrorCode));
                                                                             return;
                                                                           endif;
                                                                           
                                                                           /* Build reversal entry */
                                                                           BuildReversalEntry(pReq : origRec : revRec);
                                                                           
                                                                           /* Persist reversal */
                                                                           if not PersistReversal(revRec : newSeq);
                                                                             pRsp.ErrorCode = 'DBERR';
                                                                             pRsp.ErrorMsg  = 'Database error persisting reversal.';
                                                                             WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                                                                                             'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                                                                                             'Reversal failed: DBERR');
                                                                             return;
                                                                           endif;
                                                                           
                                                                           /* Mark original as reversed */
                                                                           if not MarkOriginalAsReversed(origRec : pReq.ReasonCode);
                                                                             // We already created reversal; flag but don't roll back here
                                                                             WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                                                                                             'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                                                                                             'Original not marked reversed after reversal.');
                                                                           endif;
                                                                           
                                                                           /* Success path */
                                                                           pRsp.Success      = *on;
                                                                           pRsp.ErrorCode    = 'OK';
                                                                           pRsp.ErrorMsg     = 'Reversal completed.';
                                                                           pRsp.NewLedgerSeq = newSeq;
                                                                           
                                                                           WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                                                                                           'REV_POST' : pReq.UserId : pReq.ReasonCode :
                                                                                           'Reversal posted; new seq=' + %editc(newSeq : 'X'));
                                                                           
                                                                           *inlr = *on;
                                                                           return;
                                                                           using System;
                                                                           using System.Runtime.InteropServices;
                                                                           using System.Text;
                                                                           
                                                                           namespace LedgerGateway
                                                                           {
                                                                               [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Ansi)]
                                                                               public struct LedgerReverseRequestBlock
                                                                               {
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 3)]
                                                                                   public string Company;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
                                                                                   public string LedgerDate; // YYYYMMDD
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 9)]
                                                                                   public string LedgerSeq;  // zero-padded
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 10)]
                                                                                   public string UserId;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 4)]
                                                                                   public string ReasonCode;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
                                                                                   public string Channel;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
                                                                                   public string RailCode;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValArray, SizeConst = 78)]
                                                                                   public byte[] Reserved;
                                                                           
                                                                                   public static LedgerReverseRequestBlock FromDomain(
                                                                                       string company,
                                                                                       DateTime ledgerDate,
                                                                                       long ledgerSeq,
                                                                                       string userId,
                                                                                       string reasonCode,
                                                                                       string channel,
                                                                                       string railCode)
                                                                                   {
                                                                                       return new LedgerReverseRequestBlock
                                                                                       {
                                                                                           Company = company.PadRight(3).Substring(0, 3),
                                                                                           LedgerDate = ledgerDate.ToString("yyyyMMdd"),
                                                                                           LedgerSeq = ledgerSeq.ToString().PadLeft(9, '0'),
                                                                                           UserId = (userId ?? string.Empty).PadRight(10).Substring(0, 10),
                                                                                           ReasonCode = (reasonCode ?? string.Empty).PadRight(4).Substring(0, 4),
                                                                                           Channel = (channel ?? string.Empty).PadRight(8).Substring(0, 8),
                                                                                           RailCode = (railCode ?? string.Empty).PadRight(8).Substring(0, 8),
                                                                                           Reserved = new byte[78]
                                                                                       };
                                                                                   }
                                                                           
                                                                                   public byte[] ToBytes()
                                                                                   {
                                                                                       int size = Marshal.SizeOf(typeof(LedgerReverseRequestBlock));
                                                                                       var buffer = new byte[size];
                                                                                       IntPtr ptr = Marshal.AllocHGlobal(size);
                                                                                       try
                                                                                       {
                                                                                           Marshal.StructureToPtr(this, ptr, false);
                                                                                           Marshal.Copy(ptr, buffer, 0, size);
                                                                                           return buffer;
                                                                                       }
                                                                                       finally
                                                                                       {
                                                                                           Marshal.FreeHGlobal(ptr);
                                                                                       }
                                                                                   }
                                                                           
                                                                                   public static LedgerReverseRequestBlock FromBytes(byte[] buffer)
                                                                                   {
                                                                                       int size = Marshal.SizeOf(typeof(LedgerReverseRequestBlock));
                                                                                       if (buffer.Length < size)
                                                                                           throw new ArgumentException("Buffer too small for request block.");
                                                                           
                                                                                       IntPtr ptr = Marshal.AllocHGlobal(size);
                                                                                       try
                                                                                       {
                                                                                           Marshal.Copy(buffer, 0, ptr, size);
                                                                                           return (LedgerReverseRequestBlock)Marshal.PtrToStructure(
                                                                                               ptr, typeof(LedgerReverseRequestBlock));
                                                                                       }
                                                                                       finally
                                                                                       {
                                                                                           Marshal.FreeHGlobal(ptr);
                                                                                       }
                                                                                   }
                                                                               }
                                                                           
                                                                               [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Ansi)]
                                                                               public struct LedgerReverseResponseBlock
                                                                               {
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1)]
                                                                                   public string Success; // 'Y' or 'N'
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 8)]
                                                                                   public string ErrorCode;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
                                                                                   public string ErrorMsg;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 9)]
                                                                                   public string NewLedgerSeq;
                                                                           
                                                                                   [MarshalAs(UnmanagedType.ByValArray, SizeConst = 30)]
                                                                                   public byte[] Reserved;
                                                                           
                                                                                   public byte[] ToBytes()
                                                                                   {
                                                                                       int size = Marshal.SizeOf(typeof(LedgerReverseResponseBlock));
                                                                                       var buffer = new byte[size];
                                                                                       IntPtr ptr = Marshal.AllocHGlobal(size);
                                                                                       try
                                                                                       {
                                                                                           Marshal.StructureToPtr(this, ptr, false);
                                                                                           Marshal.Copy(ptr, buffer, 0, size);
                                                                                           return buffer;
                                                                                       }
                                                                                       finally
                                                                                       {
                                                                                           Marshal.FreeHGlobal(ptr);
                                                                                       }
                                                                                   }
                                                                           
                                                                                   public static LedgerReverseResponseBlock FromBytes(byte[] buffer)
                                                                                   {
                                                                                       int size = Marshal.SizeOf(typeof(LedgerReverseResponseBlock));
                                                                                       if (buffer.Length < size)
                                                                                           throw new ArgumentException("Buffer too small for response block.");
                                                                           
                                                                                       IntPtr ptr = Marshal.AllocHGlobal(size);
                                                                                       try
                                                                                       {
                                                                                           Marshal.Copy(buffer, 0, ptr, size);
                                                                                           return (LedgerReverseResponseBlock)Marshal.PtrToStructure(
                                                                                               ptr, typeof(LedgerReverseResponseBlock));
                                                                                       }
                                                                                       finally
                                                                                       {
                                                                                           Marshal.FreeHGlobal(ptr);
                                                                                       }
                                                                                   }
                                                                           
                                                                                   public bool IsSuccess() => Success == "Y";
                                                                           
                                                                                   public long GetNewLedgerSeq()
                                                                                   {
                                                                                       if (string.IsNullOrWhiteSpace(NewLedgerSeq))
                                                                                           return 0;
                                                                                       if (long.TryParse(NewLedgerSeq.Trim(), out var v))
                                                                                           return v;
                                                                                       return 0;
                                                                                   }
                                                                               }
                                                                           
                                                                               public static class LedgerGatewayClient
                                                                               {
                                                                                   // This is the boundary: send 128-byte request, receive 128-byte response.
                                                                                   // Wire could be TCP, MQ, data queue, etc. Here we just show the call shape.
                                                                                   public static LedgerReverseResponseBlock CallGateway(
                                                                                       Func<byte[], byte[]> transport,
                                                                                       LedgerReverseRequestBlock request)
                                                                                   {
                                                                                       var reqBytes = request.ToBytes();
                                                                                       var rspBytes = transport(reqBytes); // must return exactly 128 bytes
                                                                                       return LedgerReverseResponseBlock.FromBytes(rspBytes);
                                                                                   }
                                                                               }
                                                                           }
                                                                                  IDENTIFICATION DIVISION.
                                                                                  PROGRAM-ID. LEDGWYCB.
                                                                                  ENVIRONMENT DIVISION.
                                                                                  CONFIGURATION SECTION.
                                                                                  SOURCE-COMPUTER. IBM-I.
                                                                                  OBJECT-COMPUTER. IBM-I.
                                                                           
                                                                                  DATA DIVISION.
                                                                                  WORKING-STORAGE SECTION.
                                                                           
                                                                                  01  WS-REQ-BLOCK-LEN          PIC 9(04) COMP VALUE 128.
                                                                                  01  WS-RSP-BLOCK-LEN          PIC 9(04) COMP VALUE 128.
                                                                           
                                                                                  01  WS-REQ-BLOCK.
                                                                                      05 WR-COMPANY             PIC X(03).
                                                                                      05 WR-LEDGER-DATE         PIC X(08).
                                                                                      05 WR-LEDGER-SEQ          PIC X(09).
                                                                                      05 WR-USER-ID             PIC X(10).
                                                                                      05 WR-REASON-CODE         PIC X(04).
                                                                                      05 WR-CHANNEL             PIC X(08).
                                                                                      05 WR-RAIL-CODE           PIC X(08).
                                                                                      05 WR-RESERVED            PIC X(78).
                                                                           
                                                                                  01  WS-RSP-BLOCK.
                                                                                      05 WS-SUCCESS             PIC X(01).
                                                                                      05 WS-ERROR-CODE          PIC X(08).
                                                                                      05 WS-ERROR-MSG           PIC X(80).
                                                                                      05 WS-NEW-LEDGER-SEQ      PIC X(09).
                                                                                      05 WS-RSP-RESERVED        PIC X(30).
                                                                           
                                                                                  01  WS-RPG-REQ.
                                                                                      05 RQ-COMPANY             PIC X(03).
                                                                                      05 RQ-LEDGER-DATE         PIC X(08).
                                                                                      05 RQ-LEDGER-SEQ          PIC 9(09).
                                                                                      05 RQ-USER-ID             PIC X(10).
                                                                                      05 RQ-REASON-CODE         PIC X(04).
                                                                                      05 RQ-CHANNEL             PIC X(08).
                                                                           
                                                                                  01  WS-RPG-RSP.
                                                                                      05 RS-SUCCESS             PIC X(01).
                                                                                      05 RS-ERROR-CODE          PIC X(08).
                                                                                      05 RS-ERROR-MSG           PIC X(128).
                                                                                      05 RS-NEW-LEDGER-SEQ      PIC 9(09).
                                                                           
                                                                                  LINKAGE SECTION.
                                                                                  01  LK-REQ-BLOCK.
                                                                                      05 LK-REQ-BYTES           PIC X(128).
                                                                           
                                                                                  01  LK-RSP-BLOCK.
                                                                                      05 LK-RSP-BYTES           PIC X(128).
                                                                           
                                                                                  PROCEDURE DIVISION USING LK-REQ-BLOCK LK-RSP-BLOCK.
                                                                           
                                                                                  MAIN-SECTION.
                                                                                      PERFORM UNPACK-REQUEST
                                                                                      PERFORM CALL-RPG-LEDGER
                                                                                      PERFORM PACK-RESPONSE
                                                                                      GOBACK.
                                                                           
                                                                                  UNPACK-REQUEST.
                                                                                      MOVE LK-REQ-BYTES TO WS-REQ-BLOCK
                                                                           
                                                                                      MOVE WR-COMPANY     TO RQ-COMPANY
                                                                                      MOVE WR-LEDGER-DATE TO RQ-LEDGER-DATE
                                                                           
                                                                                      *> ASCII numeric to COMP-3/COMP integer; here simple numeric
                                                                                      MOVE FUNCTION NUMVAL(WR-LEDGER-SEQ) TO RQ-LEDGER-SEQ
                                                                           
                                                                                      MOVE WR-USER-ID     TO RQ-USER-ID
                                                                                      MOVE WR-REASON-CODE TO RQ-REASON-CODE
                                                                                      MOVE WR-CHANNEL     TO RQ-CHANNEL.
                                                                           
                                                                                  CALL-RPG-LEDGER.
                                                                                      CALL 'LEDREVSRV'
                                                                                           USING RQ-COMPANY
                                                                                                 RQ-LEDGER-DATE
                                                                                                 RQ-LEDGER-SEQ
                                                                                                 RQ-USER-ID
                                                                                                 RQ-REASON-CODE
                                                                                                 RQ-CHANNEL
                                                                                                 RS-SUCCESS
                                                                                                 RS-ERROR-CODE
                                                                                                 RS-ERROR-MSG
                                                                                                 RS-NEW-LEDGER-SEQ.
                                                                           
                                                                                  PACK-RESPONSE.
                                                                                      IF RS-SUCCESS = 'Y'
                                                                                         MOVE 'Y' TO WS-SUCCESS
                                                                                      ELSE
                                                                                         MOVE 'N' TO WS-SUCCESS
                                                                                      END-IF
                                                                           
                                                                                      MOVE RS-ERROR-CODE TO WS-ERROR-CODE
                                                                                      MOVE RS-ERROR-MSG  TO WS-ERROR-MSG
                                                                           
                                                                                      MOVE RS-NEW-LEDGER-SEQ TO WS-NEW-LEDGER-SEQ
                                                                           
                                                                                      MOVE SPACES TO WS-RSP-RESERVED
                                                                           
                                                                                      MOVE WS-RSP-BLOCK TO LK-RSP-BYTES.
                                                                           **free
                                                                           ctl-opt dftactgrp(*no) actgrp('LEDGER') option(*srcstmt : *nodebugio);
                                                                           
                                                                           /* 128-byte request/response blocks */
                                                                           
                                                                           dcl-ds dsReqBlock qualified;
                                                                             Company      char(3);
                                                                             LedgerDate   char(8);
                                                                             LedgerSeqChr char(9);
                                                                             UserId       char(10);
                                                                             ReasonCode   char(4);
                                                                             Channel      char(8);
                                                                             RailCode     char(8);
                                                                             Reserved     char(78);
                                                                           end-ds;
                                                                           
                                                                           dcl-ds dsRspBlock qualified;
                                                                             Success      char(1);
                                                                             ErrorCode    char(8);
                                                                             ErrorMsg     char(80);
                                                                             NewSeqChr    char(9);
                                                                             Reserved     char(30);
                                                                           end-ds;
                                                                           
                                                                           /* Existing reversal API structures */
                                                                           
                                                                           dcl-ds dsReverseReq qualified;
                                                                             Company      char(3);
                                                                             LedgerDate   char(8);
                                                                             LedgerSeq    packed(9:0);
                                                                             UserId       char(10);
                                                                             ReasonCode   char(4);
                                                                             Channel      char(8);
                                                                           end-ds;
                                                                           
                                                                           dcl-ds dsReverseRsp qualified;
                                                                             Success      ind;
                                                                             ErrorCode    char(8);
                                                                             ErrorMsg     char(128);
                                                                             NewLedgerSeq packed(9:0);
                                                                           end-ds;
                                                                           
                                                                           dcl-pr LED_ReverseEntry extpgm('LEDREVSRV');
                                                                             pReq likeds(dsReverseReq) const;
                                                                             pRsp likeds(dsReverseRsp);
                                                                           end-pr;
                                                                           
                                                                           /* Binary gateway entry */
                                                                           
                                                                           dcl-pr LEDGWYRPG extpgm('LEDGWYRPG');
                                                                             pReqBlock char(128) const;
                                                                             pRspBlock char(128);
                                                                           end-pr;
                                                                           
                                                                           dcl-pi LEDGWYRPG;
                                                                             pReqBlock char(128) const;
                                                                             pRspBlock char(128);
                                                                           end-pi;
                                                                           
                                                                           dcl-s nSeq packed(9:0);
                                                                           
                                                                           /* Unpack request block */
                                                                           dsReqBlock = pReqBlock;
                                                                           
                                                                           dsReverseReq.Company    = dsReqBlock.Company;
                                                                           dsReverseReq.LedgerDate = dsReqBlock.LedgerDate;
                                                                           dsReverseReq.UserId     = dsReqBlock.UserId;
                                                                           dsReverseReq.ReasonCode = dsReqBlock.ReasonCode;
                                                                           dsReverseReq.Channel    = dsReqBlock.Channel;
                                                                           
                                                                           /* Convert ASCII numeric sequence */
                                                                           if %check('0123456789' : dsReqBlock.LedgerSeqChr) = 0;
                                                                             nSeq = %int(%dec(dsReqBlock.LedgerSeqChr : 9 : 0));
                                                                           else;
                                                                             nSeq = 0;
                                                                           endif;
                                                                           
                                                                           dsReverseReq.LedgerSeq = nSeq;
                                                                           
                                                                           /* Call core reversal engine */
                                                                           LED_ReverseEntry(dsReverseReq : dsReverseRsp);
                                                                           
                                                                           /* Pack response block */
                                                                           if dsReverseRsp.Success;
                                                                             dsRspBlock.Success = 'Y';
                                                                           else;
                                                                             dsRspBlock.Success = 'N';
                                                                           endif;
                                                                           
                                                                           dsRspBlock.ErrorCode = dsReverseRsp.ErrorCode;
                                                                           dsRspBlock.ErrorMsg  = %subst(dsReverseRsp.ErrorMsg : 1 : 80);
                                                                           
                                                                           dsRspBlock.NewSeqChr = %editc(dsReverseRsp.NewLedgerSeq : 'X');
                                                                           dsRspBlock.Reserved  = *blanks;
                                                                           
                                                                           /* Return as 128-byte char */
                                                                           pRspBlock = %subst(%char(dsRspBlock) : 1 : 128);
                                                                           
                                                                           *inlr = *on;
                                                                           return;


PROC return_item(item : Item, reason : CHAR(3)) =
    REQUIRE returnable(item).
    REQUIRE item.state != State.RETURNED.
    item.state := State.RETURNED.
    item.reason := reason.
    SAVE item.
.
'''

def compile_source(src:str, target='cobol'):
    toks = lex(src)
    p = Parser(toks)
    ast = p.parse()
    ctx, procs = build_ir(ast)
    # build maps
    records_map = ctx.records
    files_map = ctx.files
    # pick first proc
    if not procs:
        print("No procs found"); return
    proc = procs[0]
    if target=='cobol':
        out = emit_cobol_program(ctx, proc, files_map, records_map)
    elif target=='prolog':
        out = emit_prolog(ctx, proc, records_map)
    elif target=='mercury':
        out = emit_mercury(ctx, proc, records_map)
    else:
        out = "// unknown target"
    return out

# CLI
def main():
    if len(sys.argv)<2:
        print("Usage: funnelc.py <file.fnl> --target cobol|prolog|mercury")
        print("Running example and printing COBOL by default\n")
        src = EXAMPLE
        print(compile_source(src,'cobol'))
        return
    srcfile = sys.argv[1]
    target = 'cobol'
    if '--target' in sys.argv:
        target = sys.argv[sys.argv.index('--target')+1]
    with open(srcfile,'r') as f:
        src = f.read()
    out = compile_source(src,target)
    print(out)

if __name__=='__main__':
    main()
